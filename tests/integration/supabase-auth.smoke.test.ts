import { describe, expect, it } from "vitest";

import { createLocalSupabaseClients } from "../support/local-supabase";

describe("local Supabase Auth", () => {
  it("creates and cleans up an anonymous user through the local gateway", async () => {
    const { admin, browser } = createLocalSupabaseClients();
    let userId: string | undefined;

    try {
      const { data, error } = await browser.auth.signInAnonymously();
      expect(error).toBeNull();
      expect(data.session).not.toBeNull();
      expect(data.user?.is_anonymous).toBe(true);
      userId = data.user?.id;
      expect(userId).toBeTruthy();
    } finally {
      if (userId) {
        const { error } = await admin.auth.admin.deleteUser(userId);
        expect(error).toBeNull();
      }
    }
  });
});
