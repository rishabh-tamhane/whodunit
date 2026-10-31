import "server-only";

import type { SupabaseClient, User } from "@supabase/supabase-js";
import { after, NextResponse } from "next/server";
import { z } from "zod";

import type { ApiErrorCode } from "@/contracts/api/error";
import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import { recordOperationalEvent } from "@/modules/operations/telemetry.server";

const MAX_JSON_BODY_BYTES = 64 * 1024;
const requestCorrelationIds = new WeakMap<Request, string>();

export type RateLimitClass =
  | "DEFAULT"
  | "ROOM_DISCOVERY"
  | "PLAYER_CLAIM"
  | "HOST_RECOVERY"
  | "STORY_GENERATION"
  | "GAME_COMMAND";

type RateLimitPolicy = Readonly<{
  ip: number;
  principal: number;
  room?: number;
  challengeOnDenial: boolean;
}>;

const RATE_LIMIT_POLICIES: Record<RateLimitClass, RateLimitPolicy> = {
  DEFAULT: { ip: 90, principal: 120, room: 180, challengeOnDenial: false },
  ROOM_DISCOVERY: {
    ip: 30,
    principal: 45,
    challengeOnDenial: true,
  },
  PLAYER_CLAIM: {
    ip: 30,
    principal: 30,
    room: 90,
    challengeOnDenial: true,
  },
  HOST_RECOVERY: {
    ip: 12,
    principal: 15,
    challengeOnDenial: true,
  },
  STORY_GENERATION: {
    ip: 12,
    principal: 12,
    room: 6,
    challengeOnDenial: false,
  },
  GAME_COMMAND: {
    ip: 60,
    principal: 80,
    room: 120,
    challengeOnDenial: false,
  },
};

export function getRequestCorrelationId(request: Request): string {
  const existing = requestCorrelationIds.get(request);
  if (existing) return existing;
  const supplied = request.headers.get("x-request-id");
  const correlationId = z.string().uuid().safeParse(supplied).success
    ? supplied!
    : crypto.randomUUID();
  requestCorrelationIds.set(request, correlationId);
  return correlationId;
}

function requestOriginAllowed(request: Request): boolean {
  if (request.headers.get("sec-fetch-site") === "cross-site") return false;
  const origin = request.headers.get("origin");
  if (!origin) return true;
  try {
    return new URL(origin).origin === new URL(request.url).origin;
  } catch {
    return false;
  }
}

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(bytes), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function normalizedRoute(request: Request): string {
  return new URL(request.url).pathname
    .replace(
      /[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi,
      ":id",
    )
    .slice(0, 200);
}

function requestRoomId(request: Request): string | null {
  return (
    new URL(request.url).pathname.match(
      /\/rooms\/([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})(?:\/|$)/i,
    )?.[1] ?? null
  );
}

function requestIp(request: Request): string {
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    "unknown"
  );
}

async function consumeBudget(
  scope: "IP_ROUTE" | "PRINCIPAL_ROUTE" | "ROOM",
  key: string,
  limit: number,
): Promise<{ allowed: boolean; retryAfterSeconds: number } | undefined> {
  const { data, error } = await callSupabaseAdminRpc("consume_rate_limit", {
    bucket_scope: scope,
    bucket_key_hash: await sha256(key),
    maximum_requests: limit,
    window_seconds: 60,
  });
  if (error) return undefined;
  const result = data as { allowed?: boolean; retryAfterSeconds?: number };
  return {
    allowed: result.allowed === true,
    retryAfterSeconds: Math.max(1, result.retryAfterSeconds ?? 60),
  };
}

function rateLimitResponse(
  request: Request,
  retryAfterSeconds: number,
  challengeOnDenial: boolean,
) {
  const response = apiError(
    request,
    429,
    "RATE_LIMITED",
    "Too many requests. Wait briefly and try again.",
  );
  response.headers.set("Retry-After", String(retryAfterSeconds));
  if (challengeOnDenial) {
    response.headers.set("X-Whodunit-Abuse-Action", "turnstile-challenge");
  }
  return response;
}

export function noStoreJson(body: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("Cache-Control", "private, no-store, max-age=0");
  headers.set("Vary", "Cookie, Authorization");
  return NextResponse.json(body, { ...init, headers });
}

export function apiError(
  request: Request,
  status: number,
  code: ApiErrorCode,
  message: string,
  fieldErrors?: Record<string, string[]>,
) {
  return noStoreJson(
    {
      error: {
        code,
        message,
        requestId: getRequestCorrelationId(request),
        ...(fieldErrors === undefined ? {} : { fieldErrors }),
      },
    },
    { status },
  );
}

export async function parseJsonBody<T>(
  request: Request,
  schema: z.ZodType<T>,
): Promise<
  { success: true; data: T } | { success: false; response: NextResponse }
> {
  if (!requestOriginAllowed(request)) {
    return {
      success: false,
      response: apiError(
        request,
        403,
        "FORBIDDEN",
        "Cross-site mutations are not allowed.",
      ),
    };
  }
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return {
      success: false,
      response: apiError(
        request,
        400,
        "VALIDATION_ERROR",
        "Content-Type must be application/json.",
      ),
    };
  }
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_JSON_BODY_BYTES) {
    return {
      success: false,
      response: apiError(
        request,
        413,
        "VALIDATION_ERROR",
        "The request body is too large.",
      ),
    };
  }
  let payload: unknown;
  try {
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAX_JSON_BODY_BYTES)
      throw new RangeError("BODY_TOO_LARGE");
    payload = JSON.parse(rawBody);
  } catch (error) {
    if (error instanceof RangeError) {
      return {
        success: false,
        response: apiError(
          request,
          413,
          "VALIDATION_ERROR",
          "The request body is too large.",
        ),
      };
    }
    return {
      success: false,
      response: apiError(
        request,
        400,
        "VALIDATION_ERROR",
        "A valid JSON request body is required.",
      ),
    };
  }

  const parsed = schema.safeParse(payload);
  if (parsed.success) return { success: true, data: parsed.data };
  const fieldErrors = Object.fromEntries(
    Object.entries(z.flattenError(parsed.error).fieldErrors).filter(
      (entry): entry is [string, string[]] => Array.isArray(entry[1]),
    ),
  );

  return {
    success: false,
    response: apiError(
      request,
      400,
      "VALIDATION_ERROR",
      "Review the highlighted fields.",
      fieldErrors,
    ),
  };
}

export async function requireUser(
  request: Request,
  supabase: SupabaseClient,
  rateLimitClass: RateLimitClass = "DEFAULT",
): Promise<
  { success: true; user: User } | { success: false; response: NextResponse }
> {
  if (request.method !== "GET" && !requestOriginAllowed(request)) {
    return {
      success: false,
      response: apiError(
        request,
        403,
        "FORBIDDEN",
        "Cross-site mutations are not allowed.",
      ),
    };
  }
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    await recordOperationalEvent({
      correlationId: getRequestCorrelationId(request),
      eventType: "AUTHENTICATION_DENIED",
      severity: "WARNING",
      routeCode: normalizedRoute(request),
      roomId: requestRoomId(request),
      statusCode: 401,
      errorCode: "AUTHENTICATION_REQUIRED",
      metadata: { source: "AUTH" },
    });
    return {
      success: false,
      response: apiError(
        request,
        401,
        "AUTHENTICATION_REQUIRED",
        "Start or restore your guest session and try again.",
      ),
    };
  }
  const route = normalizedRoute(request);
  const pathRoomId = requestRoomId(request);
  const policy = RATE_LIMIT_POLICIES[rateLimitClass];
  const budgets = await Promise.all([
    consumeBudget("IP_ROUTE", `${requestIp(request)}|${route}`, policy.ip),
    consumeBudget(
      "PRINCIPAL_ROUTE",
      `${data.user.id}|${route}`,
      policy.principal,
    ),
    ...(pathRoomId && policy.room
      ? [consumeBudget("ROOM", `${pathRoomId}|${route}`, policy.room)]
      : []),
  ]);
  if (budgets.some((budget) => budget === undefined)) {
    await recordOperationalEvent({
      correlationId: getRequestCorrelationId(request),
      eventType: "RATE_LIMIT_UNAVAILABLE",
      severity: "ERROR",
      routeCode: route,
      roomId: pathRoomId,
      statusCode: 503,
      errorCode: "SERVICE_UNAVAILABLE",
      metadata: { source: "RATE_LIMIT" },
    });
    return {
      success: false,
      response: apiError(
        request,
        503,
        "SERVICE_UNAVAILABLE",
        "Request protection is temporarily unavailable.",
      ),
    };
  }
  const denied = budgets.find((budget) => budget && !budget.allowed);
  if (denied) {
    await recordOperationalEvent({
      correlationId: getRequestCorrelationId(request),
      eventType: "RATE_LIMIT_DENIED",
      severity: "WARNING",
      routeCode: route,
      roomId: pathRoomId,
      statusCode: 429,
      errorCode: "RATE_LIMITED",
      metadata: { source: "RATE_LIMIT", count: 1 },
    });
    return {
      success: false,
      response: rateLimitResponse(
        request,
        denied.retryAfterSeconds,
        policy.challengeOnDenial,
      ),
    };
  }
  return { success: true, user: data.user };
}

export function databaseError(
  request: Request,
  error: { code?: string; message: string },
) {
  const mapping: Record<string, { status: number; code: ApiErrorCode }> = {
    "22023": { status: 400, code: "VALIDATION_ERROR" },
    "23505": { status: 409, code: "CONFLICT" },
    "40001": { status: 409, code: "STALE_STATE_VERSION" },
    "42501": { status: 403, code: "FORBIDDEN" },
    "55000": { status: 409, code: "INVALID_ROOM_STATE" },
  };
  const mapped = mapping[error.code ?? ""] ?? {
    status: 500,
    code: "INTERNAL_ERROR" as const,
  };
  after(async () => {
    await recordOperationalEvent({
      correlationId: getRequestCorrelationId(request),
      eventType: mapped.status === 409 ? "COMMAND_CONFLICT" : "DATABASE_ERROR",
      severity: mapped.status >= 500 ? "ERROR" : "WARNING",
      routeCode: normalizedRoute(request),
      roomId: requestRoomId(request),
      statusCode: mapped.status,
      errorCode: error.code ?? mapped.code,
      metadata: { source: "DATABASE", count: 1 },
    });
  });
  return apiError(
    request,
    mapped.status,
    mapped.code,
    mapped.status === 500
      ? "The request could not be completed."
      : error.message,
  );
}
