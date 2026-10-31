import { z } from "zod";

export const STORY_SCHEMA_VERSION = "0.1.0" as const;

export const StoryEnvelopeVersionSchema = z.literal(STORY_SCHEMA_VERSION);
