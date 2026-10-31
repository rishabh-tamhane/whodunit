import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json(
    {
      status: "ok",
      version: "0.1-mvp",
    },
    {
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
}
