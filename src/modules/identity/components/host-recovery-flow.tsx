"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { z } from "zod";

import { Alert, Button, Card, StatusBadge } from "@/components/ui";
import { RecoveredHostSchema } from "@/contracts";
import { ApiClientError, requestJson } from "@/lib/api/request";

const SessionResultSchema = z.object({
  status: z.enum(["created", "restored"]),
});

function errorMessage(error: unknown) {
  return error instanceof ApiClientError
    ? error.message
    : "This recovery link could not be used.";
}

export function HostRecoveryFlow() {
  const router = useRouter();
  const [result, setResult] = useState<z.infer<typeof RecoveredHostSchema>>();
  const [error, setError] = useState<string>();
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    void (async () => {
      const fragment = new URLSearchParams(window.location.hash.slice(1));
      const token = fragment.get("token");
      window.history.replaceState({}, "", "/host/recover");
      if (!token) {
        setError("This recovery link is missing its private credential.");
        return;
      }
      try {
        await requestJson({
          url: "/api/v1/session",
          method: "POST",
          outputSchema: SessionResultSchema,
        });
        const recovered = await requestJson({
          url: "/api/v1/host-recovery",
          method: "POST",
          input: { token },
          outputSchema: RecoveredHostSchema,
        });
        setResult(recovered);
      } catch (caught) {
        setError(errorMessage(caught));
      }
    })();
  }, []);

  if (error) {
    return (
      <Alert title="Recovery did not complete" tone="danger">
        {error} Use the latest saved link from a clean guest browser, or return
        to the original Game Master device and rotate the credential.
      </Alert>
    );
  }

  if (!result) {
    return (
      <Card elevated>
        <p role="status">Verifying the private recovery credential…</p>
      </Card>
    );
  }

  const replacementUrl = new URL(result.recoveryPath, window.location.origin)
    .href;
  return (
    <Card elevated>
      <StatusBadge tone="success">Game Master restored</StatusBadge>
      <h1 className="mt-4 text-3xl font-black">Save the replacement link</h1>
      <p className="mt-3 leading-7 text-stone-300">
        The old Game Master session and old recovery link no longer control room{" "}
        {result.roomCode}. This rotated link is shown once.
      </p>
      <div className="mt-5 break-all rounded-xl border border-white/10 bg-black/25 p-4 font-mono text-sm text-orange-200">
        {replacementUrl}
      </div>
      <Button
        className="mt-4"
        variant="secondary"
        onClick={() => navigator.clipboard.writeText(replacementUrl)}
      >
        Copy replacement link
      </Button>
      <label className="mt-6 flex min-h-11 items-center gap-3 text-sm font-bold">
        <input
          type="checkbox"
          className="size-5"
          checked={saved}
          onChange={(event) => setSaved(event.target.checked)}
        />
        I saved the replacement recovery link.
      </label>
      <Button
        className="mt-5 w-full sm:w-auto"
        disabled={!saved}
        onClick={() => {
          router.push(`/host/rooms/${result.roomId}`);
        }}
      >
        Open Game Master control
      </Button>
    </Card>
  );
}
