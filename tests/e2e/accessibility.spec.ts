import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const publicSurfaces = [
  { path: "/", readyName: "Make the party a mystery." },
  { path: "/join", readyName: "Join your mystery." },
  {
    path: "/host",
    readyName: "You run the game. You never play a character.",
  },
] as const;

test.describe("automated accessibility and responsive checks", () => {
  test("has no serious WCAG A/AA violations on public entry surfaces", async ({
    page,
  }) => {
    for (const surface of publicSurfaces) {
      await page.goto(surface.path);
      await expect(
        page.getByRole("heading", { name: surface.readyName }),
      ).toBeVisible();
      if (surface.path === "/join") {
        await expect(page.getByLabel("Room code")).toBeVisible();
      }
      if (surface.path === "/host") {
        await expect(
          page.getByRole("button", { name: "Create room" }),
        ).toBeVisible();
      }

      const result = await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
        .analyze();
      expect(result.violations).toEqual([]);
    }
  });

  test("preserves focus, touch targets, reduced motion, and narrow layouts", async ({
    page,
  }, testInfo) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/");
    const homeLink = page.getByRole("link", { name: "Whodunit" });
    if (testInfo.project.name.includes("webkit")) {
      // WebKit follows the macOS full-keyboard-access preference for Tab.
      // Programmatic focus still verifies the application's visible style;
      // manual Safari coverage owns the platform preference itself.
      await homeLink.focus();
    } else {
      await page.keyboard.press("Tab");
    }
    await expect(homeLink).toBeFocused();
    const focusStyle = await homeLink.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        outlineStyle: style.outlineStyle,
        outlineWidth: Number.parseFloat(style.outlineWidth),
      };
    });
    expect(focusStyle.outlineStyle).not.toBe("none");
    expect(focusStyle.outlineWidth).toBeGreaterThanOrEqual(3);

    const createAction = page.getByRole("link", {
      name: "Create a mystery",
    });
    const actionBox = await createAction.boundingBox();
    expect(actionBox?.height).toBeGreaterThanOrEqual(44);
    const reducedDuration = await createAction.evaluate((element) =>
      Number.parseFloat(getComputedStyle(element).transitionDuration),
    );
    expect(reducedDuration).toBeLessThanOrEqual(0.01);

    await page.goto("/join");
    const input = page.getByLabel("Room code");
    await expect(input).toHaveAccessibleName("Room code");
    await input.fill("ऋतु-चट्टोपाध्याय-श्रीनिवासन-🎃".repeat(3));
    const metrics = await page.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));
    expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.clientWidth + 1);
  });
});
