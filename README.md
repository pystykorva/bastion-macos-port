# Tessu

> **A native macOS port of [Bastion](https://github.com/0xCodez/bastion) by the Bastion contributors.**
> This is a fork of that project, rewritten in Swift and SwiftUI. It is not affiliated with, endorsed by or
> maintained by the original authors. Original work © 2026 Bastion contributors, MIT licence.

Close your router's backdoors, see where your traffic goes, tune your Wi-Fi, and let an AI explain what it
finds. A free, open-source checkup for your home network that runs entirely on your Mac.

- **Native**: SwiftUI and Apple system frameworks only. No Electron, no web view, no Node. About 10 MB.
- **Honest**: a check that cannot be measured from this Mac says *unknown*. It is never shown as fine.
- **Private**: scans run on your Mac. Only a question you ask an AI sends anything, and it is stripped of
  Wi-Fi names, device names, MAC addresses and the end of your public IP.
- **Read-only**: Tessu never logs in to your router, never tries passwords and never changes a setting.
  AI agents can only answer.

## What it does

| Screen | What you get |
|---|---|
| Home | Verdict, score, what needs attention, last speed result |
| Shield | 12 router and Wi-Fi checks (TR-069, UPnP, Telnet, SSH, admin page encryption, DNS, Wi-Fi security, ...), a 2D exposure radar, ranked findings with fix steps |
| Speed & Wi-Fi | Speed test (ping, jitter, down, up), link details, channel chart with a recommended channel |
| Devices | Devices seen on the network, and this Mac's connections grouped by program |
| Agents | Ask Claude, ChatGPT, Grok, OpenRouter, a local model, or your Claude Code / Codex subscription. Optional watch mode |
| Settings | API keys (Keychain), subscription CLIs, local server, scan and alert preferences, a preview of exactly what an AI is sent |
| Support, Credits | Feedback, and the licences |

## How this port differs from the original

| | Original (Electron) | This port |
|---|---|---|
| Platforms | Windows and macOS | macOS 14+ only |
| UI | HTML/JS, three.js 3D hero and radar | SwiftUI; **the 3D scenes are gone** (decorative), the radar is a flat 2D chart with a findings list beside it |
| Engine | Node, parses `netsh`, `system_profiler`, ... | Swift; CoreWLAN for Wi-Fi, BSD sockets for probes |
| API keys | Electron `safeStorage` | macOS Keychain |
| AI providers | Claude, ChatGPT, Grok, Claude Code, Codex | the same, plus **OpenRouter** and a **local server** (LM Studio, Ollama, llama.cpp, vLLM, ...) |
| Voice input | Local Whisper model | not ported |
| Tip jar | third-party service | not ported |
| Feedback | built-in address | opens your mail app or browser; the destination is set by whoever builds the app |

What carries over from the original: the 12 checks and their wording, the scoring, the Wi-Fi channel advice
logic, the privacy filter for AI questions, the router-vendor table, and the Claude Code / Codex lockdown
approach. See the Credits screen in the app and `LICENSE`.

## Build

You need macOS 14+ and Xcode 16+.

```bash
swift build
swift test
swift run tessu-smoke scan     # also: wifi, devices, dns, connections, speed, local
./scripts/package.sh             # dist/Tessu.app + dist/Tessu-<version>.dmg (ad-hoc signed)
```

Signed and notarized: `SIGN_ID="Developer ID Application: ..." NOTARY_PROFILE=name ./scripts/package.sh`.
Builds are not signed or notarized by default, so Gatekeeper will warn on other Macs.

## Permissions

- **Local Network**: without it macOS hides your devices and this Mac's Wi-Fi address. Tessu detects this
  and says so instead of reporting "no devices".
- **Location Services**: macOS hides Wi-Fi network names without it. Only the name and channel are read.

## Privacy

Tessu contacts only: `speed.cloudflare.com` (speed test), `api.ipify.org` (your public IP), and the AI you
choose (`api.anthropic.com`, `api.openai.com`, `api.x.ai`, `openrouter.ai`, or your own local server). No
analytics, no accounts. A local server on this Mac keeps questions on this Mac; an address elsewhere needs
your confirmation.

## Disclaimer

Provided as is, without warranty. It gives guidance based on what it can observe from this Mac and cannot
guarantee that a network is secure. Only scan networks you own or are allowed to test. Changing router
settings can interrupt your connection: write down the current values first. Product names belong to their
owners.

## Contributing and security

See `CONTRIBUTING.md` and `SECURITY.md`. Bugs in the original Electron app belong in the
[upstream project](https://github.com/0xCodez/bastion/issues).

## Licence

MIT. Copyright © 2026 Bastion contributors (original) and the macOS port's author. See `LICENSE`.
