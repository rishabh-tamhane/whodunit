import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

import { getServerEnv } from "@/lib/env/server";

export async function createSupabaseServerClient() {
  const cookieStore = await cookies();
  const env = getServerEnv();

  return createServerClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (cookiesToSet) => {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, {
                ...options,
                path: options.path ?? "/",
                sameSite: options.sameSite ?? "lax",
                secure: env.NODE_ENV === "production",
              });
            }
          } catch {
            // Server Components cannot set cookies. Route handlers and server
            // actions perform refresh writes when a response can carry them.
          }
        },
      },
    },
  );
}
