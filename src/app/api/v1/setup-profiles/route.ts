import {
  databaseError,
  noStoreJson,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;

  const { data, error } = await supabase.rpc("get_room_setup_profiles");
  if (error) return databaseError(request, error);
  return noStoreJson(data);
}
