import { z } from "zod";

import {
  ApiErrorEnvelopeSchema,
  type ApiErrorCode,
  type ApiErrorEnvelope,
} from "@/contracts/api/error";
import type { DomainCommandMetadata } from "@/contracts/api/command";
import {
  IdempotencyKeySchema,
  type StateVersion,
} from "@/contracts/domain/ids";

export class ApiClientError extends Error {
  readonly code: ApiErrorCode;
  readonly requestId: string;
  readonly fieldErrors: Record<string, string[]> | undefined;
  readonly currentStateVersion: StateVersion | undefined;
  readonly status: number;

  constructor(
    envelope: ApiErrorEnvelope,
    status: number,
    options?: ErrorOptions,
  ) {
    super(envelope.error.message, options);
    this.name = "ApiClientError";
    this.code = envelope.error.code;
    this.requestId = envelope.error.requestId;
    this.fieldErrors = envelope.error.fieldErrors;
    this.currentStateVersion = envelope.error.currentStateVersion;
    this.status = status;
  }
}

export type MutationMetadata = Readonly<DomainCommandMetadata>;

export type MutationState<T> =
  | { status: "idle"; data?: T }
  | { status: "submitting"; data?: T; optimisticData?: T }
  | { status: "success"; data: T }
  | { status: "conflict"; data?: T; currentStateVersion?: StateVersion }
  | { status: "error"; data?: T; error: ApiClientError };

export function beginOptimisticMutation<T>(
  data: T | undefined,
  optimisticData?: T,
): MutationState<T> {
  return {
    status: "submitting",
    ...(data === undefined ? {} : { data }),
    ...(optimisticData === undefined ? {} : { optimisticData }),
  };
}

export function createIdempotencyKey() {
  return IdempotencyKeySchema.parse(globalThis.crypto.randomUUID());
}

export async function recoverMutationFailure<T>(
  error: unknown,
  refetch: () => Promise<T>,
): Promise<MutationState<T>> {
  if (
    error instanceof ApiClientError &&
    error.status === 409 &&
    ["CONFLICT", "STALE_STATE_VERSION"].includes(error.code)
  ) {
    const data = await refetch();
    return {
      status: "conflict",
      data,
      ...(error.currentStateVersion === undefined
        ? {}
        : { currentStateVersion: error.currentStateVersion }),
    };
  }

  const normalized =
    error instanceof ApiClientError
      ? error
      : new ApiClientError(fallbackEnvelope(500), 500, { cause: error });
  return { status: "error", error: normalized };
}

type RequestOptions<Input, Output> = {
  url: string;
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  input?: Input;
  inputSchema?: z.ZodType<Input>;
  outputSchema: z.ZodType<Output>;
  metadata?: MutationMetadata;
  signal?: AbortSignal;
  fetcher?: typeof fetch;
  maxAttempts?: number;
  wait?: (milliseconds: number) => Promise<void>;
};

function fallbackEnvelope(status: number): ApiErrorEnvelope {
  return {
    error: {
      code:
        status === 401
          ? "AUTHENTICATION_REQUIRED"
          : status === 403
            ? "FORBIDDEN"
            : status === 404
              ? "NOT_FOUND"
              : status === 409
                ? "CONFLICT"
                : status === 429
                  ? "RATE_LIMITED"
                  : status >= 500
                    ? "SERVICE_UNAVAILABLE"
                    : "INTERNAL_ERROR",
      message: "The request could not be completed.",
      requestId: "unavailable",
    },
  };
}

async function readJson(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return undefined;
  }

  return response.json();
}

function retryDelay(response: Response): number {
  const retryAfter = response.headers.get("retry-after");
  if (!retryAfter) return 250;
  const seconds = Number(retryAfter);
  return Number.isFinite(seconds) ? Math.max(0, seconds * 1000) : 250;
}

export async function requestJson<Input, Output>({
  url,
  method = "GET",
  input,
  inputSchema,
  outputSchema,
  metadata,
  signal,
  fetcher = fetch,
  maxAttempts = metadata ? 2 : 1,
  wait = (milliseconds) =>
    new Promise((resolve) => globalThis.setTimeout(resolve, milliseconds)),
}: RequestOptions<Input, Output>): Promise<Output> {
  const parsedInput =
    inputSchema && input !== undefined ? inputSchema.parse(input) : input;
  const headers = new Headers({ Accept: "application/json" });

  if (parsedInput !== undefined)
    headers.set("Content-Type", "application/json");
  if (metadata) {
    headers.set("Idempotency-Key", metadata.idempotencyKey);
    headers.set(
      "X-Expected-State-Version",
      String(metadata.expectedStateVersion),
    );
  }

  let lastNetworkError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    let response: Response;
    try {
      const requestInit: RequestInit = {
        method,
        headers,
        cache: "no-store",
        credentials: "same-origin",
        ...(parsedInput === undefined
          ? {}
          : { body: JSON.stringify(parsedInput) }),
        ...(signal === undefined ? {} : { signal }),
      };
      response = await fetcher(url, requestInit);
    } catch (error) {
      lastNetworkError = error;
      if (attempt < maxAttempts) {
        await wait(250);
        continue;
      }
      throw new ApiClientError(fallbackEnvelope(503), 503, { cause: error });
    }

    const payload = await readJson(response);

    if (response.ok) return outputSchema.parse(payload);

    if (
      [429, 502, 503, 504].includes(response.status) &&
      attempt < maxAttempts
    ) {
      await wait(retryDelay(response));
      continue;
    }

    const envelope = ApiErrorEnvelopeSchema.safeParse(payload);
    throw new ApiClientError(
      envelope.success ? envelope.data : fallbackEnvelope(response.status),
      response.status,
    );
  }

  throw new ApiClientError(fallbackEnvelope(503), 503, {
    cause: lastNetworkError,
  });
}
