import type { StoryPackage } from "@/contracts/story/package";

function normalize(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(normalize);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, child]) => [key, normalize(child)]),
    );
  }
  return value;
}

export function canonicalSerialize(value: unknown): string {
  return JSON.stringify(normalize(value));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function serializeStoryPackage(story: StoryPackage): string {
  return canonicalSerialize(story);
}

export async function checksumStoryPackage(
  story: StoryPackage,
): Promise<string> {
  return sha256Hex(serializeStoryPackage(story));
}

export async function checksumStorySolution(
  story: StoryPackage,
): Promise<string> {
  return sha256Hex(
    canonicalSerialize({ victim: story.victim, solution: story.solution }),
  );
}
