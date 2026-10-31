function invalidEnvironmentFields(error: unknown): string[] {
  if (typeof error !== "object" || error === null || !("issues" in error)) {
    return [];
  }

  const issues = (error as { issues?: unknown }).issues;
  if (!Array.isArray(issues)) {
    return [];
  }

  return [
    ...new Set(
      issues.flatMap((issue) => {
        if (
          typeof issue !== "object" ||
          issue === null ||
          !("path" in issue) ||
          !Array.isArray(issue.path)
        ) {
          return [];
        }

        const path: unknown[] = issue.path;
        const field = path
          .filter(
            (segment: unknown): segment is string | number =>
              typeof segment === "string" || typeof segment === "number",
          )
          .join(".");

        return field ? [field] : [];
      }),
    ),
  ].sort();
}

export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME !== "nodejs") {
    return;
  }

  const { getServerEnv } = await import("@/lib/env/server");

  try {
    getServerEnv();
  } catch (error) {
    const invalidFields = invalidEnvironmentFields(error);
    const fieldSummary = invalidFields.length
      ? ` Invalid fields: ${invalidFields.join(", ")}.`
      : "";

    throw new Error(
      `Whodunit cannot start because its server configuration is missing or malformed.${fieldSummary} Check .env.local against .env.example.`,
    );
  }
}
