"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { z } from "zod";

import { ActorViewSchema } from "@/contracts";
import { ApiClientError, requestJson } from "@/lib/api/request";
import { getSupabaseBrowserClient } from "@/lib/supabase/browser";

export type ActorView = z.infer<typeof ActorViewSchema>;

export function useActorProjection(roomId: string, initialView?: ActorView) {
  const [view, setView] = useState<ActorView | undefined>(initialView);
  const [error, setError] = useState<string>();
  const [connection, setConnection] = useState<
    "CONNECTED" | "RECONNECTING" | "OFFLINE"
  >(
    typeof navigator !== "undefined" && !navigator.onLine
      ? "OFFLINE"
      : "CONNECTED",
  );
  const versionRef = useRef(initialView?.room.stateVersion);

  const refresh = useCallback(async () => {
    try {
      const next = await requestJson({
        url: `/api/v1/rooms/${roomId}/view`,
        outputSchema: ActorViewSchema,
      });
      versionRef.current = next.room.stateVersion;
      setView(next);
      setError(undefined);
      setConnection(navigator.onLine ? "CONNECTED" : "OFFLINE");
      return next;
    } catch (caught) {
      setConnection(navigator.onLine ? "RECONNECTING" : "OFFLINE");
      setError(
        caught instanceof ApiClientError
          ? caught.message
          : "Updates are delayed. Reconnecting…",
      );
      throw caught;
    }
  }, [roomId]);

  useEffect(() => {
    const supabase = getSupabaseBrowserClient();
    const channel = supabase
      .channel(`room-signals:${roomId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "room_signals",
          filter: `room_id=eq.${roomId}`,
        },
        (payload: { new: Record<string, unknown> }) => {
          const signaledVersion = String(
            (payload.new as { state_version?: unknown }).state_version ?? "",
          );
          if (signaledVersion !== versionRef.current)
            void refresh().catch(() => undefined);
        },
      )
      .subscribe((status: string) => {
        if (status === "SUBSCRIBED") setConnection("CONNECTED");
        if (["CHANNEL_ERROR", "TIMED_OUT"].includes(status))
          setConnection("RECONNECTING");
      });
    const poll = window.setInterval(() => {
      if (document.visibilityState === "visible")
        void refresh().catch(() => undefined);
    }, 5_000);
    const onFocus = () => void refresh().catch(() => undefined);
    const onOnline = () => {
      setConnection("RECONNECTING");
      void refresh().catch(() => undefined);
    };
    const onOffline = () => setConnection("OFFLINE");
    window.addEventListener("focus", onFocus);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.clearInterval(poll);
      window.removeEventListener("focus", onFocus);
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
      void supabase.removeChannel(channel);
    };
  }, [refresh, roomId]);

  return { view, error, connection, refresh };
}
