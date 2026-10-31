import type { Metadata } from "next";

import { HostRecoveryFlow } from "@/modules/identity/components/host-recovery-flow";

export const metadata: Metadata = { title: "Recover Game Master" };

export default function HostRecoveryPage() {
  return (
    <main className="mx-auto min-h-screen w-full max-w-2xl px-5 py-12">
      <HostRecoveryFlow />
    </main>
  );
}
