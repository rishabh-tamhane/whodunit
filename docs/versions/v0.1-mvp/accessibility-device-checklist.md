# v0.1 Accessibility and Device Verification

This is the human release record for QA-08. Automated checks run in
`npm run test:e2e`; this document must be completed against one immutable
release-candidate commit and deployment before QA-08 can close.

## Automated baseline

The browser suite performs axe WCAG A/AA scans on the home, join, and Game
Master entry surfaces in desktop Chromium, mobile Chromium emulation, and
WebKit. It also checks visible focus, a 44 px primary action, reduced-motion
styles, 360 px page overflow, long Unicode text, and narrow Game Master/player
screens containing a 12-player room. WebKit runs the application's focus style
programmatically because Safari's Tab behavior depends on the operating
system's Full Keyboard Access preference.

Record the candidate evidence:

| Field | Value |
|---|---|
| Commit | _pending_ |
| Preview/staging URL | _pending_ |
| `npm run check` | _pending_ |
| `CI=true npm run db:verify` | _pending_ |
| Automated violations | _pending_ |

## Supported-device matrix

Use synthetic rooms only. Record the exact OS/browser version, tester, date,
and result. `Blocked` is not a pass and needs a linked release decision.

| Surface | Required environment | Result | Evidence / defect |
|---|---|---|---|
| Player | iPhone, latest Safari | _pending_ | |
| Player | iPhone, previous-major Safari | _pending_ | |
| Player | Android, latest Chrome | _pending_ | |
| Player | Android, previous-major Chrome | _pending_ | |
| Game Master | macOS Safari, latest | _pending_ | |
| Game Master | macOS Chrome, latest | _pending_ | |
| Game Master | Windows Edge, latest | _pending_ | |
| Game Master | Windows Chrome, latest | _pending_ | |

## Manual accessibility pass

Run the complete create → join → claim → onboarding → dossier → mission →
notebook → final case → reveal path. Include the long name
`ऋतु चट्टोपाध्याय-श्रीनिवासन 🎃` and a duplicate display name.

- [ ] Keyboard-only use has a logical order, visible focus, no traps, and a
      usable dialog/tab pattern. On Safari, enable Full Keyboard Access first.
- [ ] VoiceOver on iOS/macOS or TalkBack on Android announces page headings,
      labels, errors, status changes, selected tabs, disabled controls, and
      connection state without reading decorative content.
- [ ] At 200% browser zoom, content reflows without hidden controls or page
      horizontal scrolling; intentional tab strips remain locally scrollable.
- [ ] At 360 × 640 CSS pixels, every player action remains reachable and the
      Game Master can inspect and control a 12-player room.
- [ ] With Reduce Motion enabled, no important state depends on animation and
      transitions are effectively removed.
- [ ] Text and interactive-state contrast is readable in normal, hover, focus,
      disabled, success, warning, and danger states; color is never the only
      cue.
- [ ] Touch targets are comfortable on physical phones and no adjacent
      destructive/confirm actions are easy to hit accidentally.
- [ ] Refresh, temporary offline mode, reconnect, and stale-state recovery are
      announced and do not move focus unexpectedly.
- [ ] Screen orientation changes preserve the current route, entered drafts,
      and visible control context.

## Sign-off

QA-08 passes only when every required matrix row passes, no critical issue is
open, and any serious exception has an owner, mitigation, expiry, and rollback
condition in the release checklist.

| Role | Name | Date | Decision |
|---|---|---|---|
| QA/accessibility | _pending_ | _pending_ | _pending_ |
| Product | _pending_ | _pending_ | _pending_ |
