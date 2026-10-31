import { createSupabaseServerClient } from "@/lib/supabase/server";
import { apiError, noStoreJson } from "@/lib/api/route.server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const supabase = await createSupabaseServerClient();
  const existing = await supabase.auth.getUser();
  if (existing.data.user) {
    return noStoreJson({ status: "restored" });
  }

  const { data, error } = await supabase.auth.signInAnonymously();
  if (error || !data.user || !data.session) {
    return apiError(
      request,
      503,
      "SERVICE_UNAVAILABLE",
      "A private guest session could not be started. Try again.",
    );
  }

  return noStoreJson({ status: "created" }, { status: 201 });
}
