import { RecoverHostInputSchema, RecoveredHostSchema } from "@/contracts";
import {
  apiError,
  noStoreJson,
  parseJsonBody,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  createRecoveryCredential,
  digestRecoveryToken,
} from "@/modules/identity/recovery.server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const parsed = await parseJsonBody(request, RecoverHostInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase, "HOST_RECOVERY");
  if (!authorization.success) return authorization.response;
  const replacement = createRecoveryCredential();
  const { data, error } = await supabase.rpc("recover_game_master", {
    recovery_token_digest: digestRecoveryToken(parsed.data.token),
    replacement_token_digest: replacement.digestForDatabase,
    replacement_expires_at: replacement.expiresAt.toISOString(),
  });
  if (error)
    return apiError(
      request,
      404,
      "NOT_FOUND",
      "This recovery link is invalid, expired, or already replaced.",
    );
  const result = RecoveredHostSchema.omit({ recoveryPath: true }).safeParse(
    data,
  );
  if (!result.success) {
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "The recovered room response was invalid.",
    );
  }
  return noStoreJson({
    ...result.data,
    recoveryPath: `/host/recover#token=${encodeURIComponent(replacement.token)}`,
  });
}
