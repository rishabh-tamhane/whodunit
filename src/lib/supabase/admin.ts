import "server-only";

import { createClient } from "@supabase/supabase-js";

import { getServerEnv } from "@/lib/env/server";

let adminClient: ReturnType<typeof createClient> | undefined;

export function getSupabaseAdminClient() {
  if (adminClient) {
    return adminClient;
  }

  const env = getServerEnv();
  adminClient = createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
  return adminClient;
}

export async function callSupabaseAdminRpc(
  functionName: string,
  args: Record<string, unknown> = {},
): Promise<{
  data: unknown;
  error: { code?: string; message: string } | null;
}> {
  const rpc = getSupabaseAdminClient().rpc as unknown as (
    name: string,
    parameters: Record<string, unknown>,
  ) => Promise<{
    data: unknown;
    error: { code?: string; message: string } | null;
  }>;
  return rpc(functionName, args);
}
