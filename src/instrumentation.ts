export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME !== "nodejs") {
    return;
  }

  const { getServerEnv } = await import("@/lib/env/server");

  try {
    getServerEnv();
  } catch {
    throw new Error(
      "Whodunit cannot start because its server configuration is missing or malformed. Check .env.local against .env.example.",
    );
  }
}
