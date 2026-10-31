import "server-only";

import type { SupabaseClient, User } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { z } from "zod";

import type { ApiErrorCode } from "@/contracts/api/error";

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
        requestId: request.headers.get("x-request-id") ?? crypto.randomUUID(),
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
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
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
): Promise<
  { success: true; user: User } | { success: false; response: NextResponse }
> {
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
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
  return apiError(
    request,
    mapped.status,
    mapped.code,
    mapped.status === 500
      ? "The request could not be completed."
      : error.message,
  );
}
