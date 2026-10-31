import { createClient } from "@supabase/supabase-js";

import { getIntegrationEnv } from "./integration-env";

const authOptions = {
  autoRefreshToken: false,
  detectSessionInUrl: false,
  persistSession: false,
} as const;

export function createLocalSupabaseClients() {
  const env = getIntegrationEnv();

  return {
    admin: createClient(
      env.NEXT_PUBLIC_SUPABASE_URL,
      env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: authOptions },
    ),
    browser: createClient(
      env.NEXT_PUBLIC_SUPABASE_URL,
      env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      { auth: authOptions },
    ),
  };
}
