import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import {
  Alert,
  Button,
  Dialog,
  EvidenceCard,
  MissionCard,
  PlayerCard,
  StatusBadge,
  Tabs,
  Toast,
} from "@/components/ui";

describe("mobile UI primitives", () => {
  it("keeps actions at an accessible touch target and native disabled state", () => {
    const html = renderToStaticMarkup(
      <Button disabled>Generate mystery</Button>,
    );
    expect(html).toContain("min-h-11");
    expect(html).toContain("disabled");
    expect(html).toContain("Generate mystery");
  });

  it("renders long Unicode player identities without using names as keys", () => {
    const name = "அனன்யா श्रीनिवासन — மிக நீண்ட பெயர்";
    const html = renderToStaticMarkup(
      <PlayerCard
        name={name}
        costume="રાણી લક્ષ્મીબાઈ inspired time traveller"
        status="Connected"
        statusTone="success"
      />,
    );
    expect(html).toContain(name);
    expect(html).toContain("break-words");
    expect(html).toContain("Connected");
  });

  it("provides semantic status, alert, dialog, and current-tab affordances", () => {
    const html = renderToStaticMarkup(
      <>
        <StatusBadge tone="warning">Pending</StatusBadge>
        <Alert title="Room expires soon" tone="danger">
          Take a valid action to keep it.
        </Alert>
        <Toast title="Saved">Notebook synchronized.</Toast>
        <Dialog
          open
          title="Approve this device?"
          description="This replaces the old phone."
        >
          Device request
        </Dialog>
        <Tabs
          label="Game Master sections"
          activeId="players"
          tabs={[
            { id: "players", label: "Players", href: "/players", count: 12 },
          ]}
        />
      </>,
    );
    expect(html).toContain('role="status"');
    expect(html).toContain('aria-label="Room expires soon"');
    expect(html).toContain('aria-labelledby="dialog-title"');
    expect(html).toContain('aria-current="page"');
  });

  it("renders evidence and mission copy as text with explicit audience and state", () => {
    const html = renderToStaticMarkup(
      <>
        <EvidenceCard
          kind="Testimony"
          title="The stopped clock"
          audience="Everyone"
        >
          The clock stopped at 11:47.
        </EvidenceCard>
        <MissionCard
          status="Active"
          title="Compare alibis"
          objective="Ask Priya where she was before midnight."
          stakes="Completing this may release a clue."
        />
      </>,
    );
    expect(html).toContain("Everyone");
    expect(html).toContain("Active");
    expect(html).not.toContain("dangerouslySetInnerHTML");
  });
});
