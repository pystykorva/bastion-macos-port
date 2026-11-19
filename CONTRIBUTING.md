# Contributing to Tessu

Thanks for helping make home networks a little less leaky.

This is a native Swift port of [Bastion](https://github.com/0xCodez/bastion) by the Bastion contributors.
Bugs in the original Electron app (including its Windows build) belong in that project. This repository
only covers the native macOS app.

## Ground rules

1. **Never fake data.** If something cannot be measured from this Mac, the app says `unknown` and explains
   how the user can find out. A missing measurement is `nil` in the engine, never a zero. A privacy block
   (Local Network, Location) must show as a block, never as "no devices" or "not randomized".
2. **Never touch settings silently.** Read-only checks need no admin rights. Anything that would change
   the Mac or the router is a guided fix: clear steps plus a button that opens the right settings page.
   The user always makes the change.
3. **Never send data off the machine** except the hosts listed under Privacy in the README and in the app's
   Settings. A new outbound host needs a strong reason and an update to both.
4. **Everything an AI sees goes through `PromptBuilder`.** It is a whitelist. If a new field is added to the
   snapshot, add a test in `PromptPrivacyTests` showing that nothing identifying can leak through it.
5. **Agents only answer.** Nothing may let a model run a command, read a file or change a setting. Changes
   to the Claude Code / Codex lockdown flags need a test and a note in `SECURITY.md`.
6. **No secrets or personal addresses in the source.** The Support destination is injected at build time
   (see below). A test fails if an email address or tracker URL is committed.

## Setup

You need macOS 14 or newer and Xcode 16 or newer (Swift 6 toolchain).

```bash
git clone https://github.com/pystykorva/tessu.git
cd tessu
swift build                 # debug build
swift test                  # unit tests
swift run tessu-smoke scan   # run the real engine against your own network (also: wifi, devices, dns, connections, speed)
./scripts/package.sh        # dist/Tessu.app and a .dmg, ad-hoc signed
```

Layout:

- `Sources/TessuCore`: the engine. No UI. Scans, Wi-Fi (CoreWLAN), UPnP, DNS, speed test, AI providers,
  Keychain storage, prompt filtering.
- `Sources/Tessu`: the SwiftUI app. Views contain no network logic.
- `Sources/TessuSmoke`: command-line harness for the engine.
- `Tests/TessuCoreTests`: unit tests. Parsers are tested against captured command output in `Fixtures/`.

## Code style

- Engine functions resolve with data and collect problems in an `errors` field instead of throwing.
- Run system tools through `Exec` (no shell, timeout, process group). Never build shell strings.
- Parse command output defensively and add a fixture and a test for every new format you handle.
- Prefer system frameworks. A new third-party dependency needs a reason, and its licence goes on the
  Credits screen.
- Plain language over jargon in anything the user reads: "Your provider can reach your router" beats
  "TR-069 CWMP endpoint exposed".
- Status is never colour alone: pair it with a shape or a word, and respect Reduce Motion.
- Keep files under about 300 lines; split by concern.

## Pull requests

- Keep them focused. One fix or feature per pull request.
- Run `swift test` and start the app before opening the PR. Say which macOS version and Mac you tested on.
- If a check's result depends on router hardware, name the router model you tested with.
- New security checks must include the exact evidence shown to the user and a fix with concrete steps.
- Screenshots for UI changes.

## Building a release (maintainers)

`scripts/package.sh` reads the Support destination from `TESSU_FEEDBACK_EMAIL` and
`TESSU_FEEDBACK_ISSUES_URL`, from the environment or from an untracked `.release.env`
(copy `.release.env.example`). Without them the built app has no feedback address. Do not commit real values.

## Reporting bugs

Use the bug report template. For security issues in Tessu itself, follow `SECURITY.md` instead.
