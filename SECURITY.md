# Security policy

Tessu is a security tool, so bugs in Tessu itself are taken seriously.

This is a native port of [Bastion](https://github.com/0xCodez/bastion) by the Bastion contributors. It shares
no code with the Electron app beyond the data tables and check wording, so a vulnerability in one is not
necessarily in the other. Report to the project the affected code belongs to:

- the **native macOS app** (this repository): follow the steps below;
- the **original Electron app** (Windows and macOS): see the
  [upstream security policy](https://github.com/0xCodez/bastion/blob/main/SECURITY.md).

## Reporting a vulnerability

Please **do not open a public issue** for a vulnerability.

Use GitHub's private reporting instead: open this repository's **Security** tab and choose
**Report a vulnerability**. Include:

- the Tessu version (Credits screen) and your macOS version and Mac type (Apple Silicon / Intel),
- what an attacker can do and what they need (local user, same network, malicious router response,
  malicious AI or local-server response, a hostile device on the network, ...),
- steps to reproduce or a proof of concept,
- any suggested fix.

You should get an acknowledgement within 7 days. We will keep you posted while a fix is prepared and
credit you in the release notes unless you prefer not to be named.

## Supported versions

Only the latest release receives security fixes. Tessu is pre-1.0; please update before reporting.

## What is in scope

- Anything that lets a network peer, a router response, a UPnP description, an AI model response or a
  local-server response run code, read files, or make Tessu act outside its job.
- Leaks of stored API keys (they live in the macOS Keychain, readable only while the Mac is unlocked and
  never synced) or of network data to any host other than the ones listed under Privacy in the README.
- Identifying data reaching an AI provider that the privacy filter promises to remove (Wi-Fi names, device
  names, full MAC addresses, this Mac's name, the last part of the public IP).
- Prompt injection that makes an agent claim to have changed something, or that changes what Tessu does.
- Tessu changing a setting on your Mac or router without your explicit approval.
- Command injection through values parsed from system tools (`route`, `arp`, `lsof`, `scutil`,
  `networksetup`, `ifconfig`) or through the Claude Code / Codex integration.
- A local-server address outside this Mac being used without the user's confirmation.
- Checks that report "OK" when the risk is demonstrably present (false reassurance).
- A feedback destination reaching someone other than the developer who built the app (see the Support
  design rule below).

## Out of scope

- Vulnerabilities in your router, ISP equipment or other devices. Tessu helps you find some of
  them; please report those to the vendor.
- Findings that require an already compromised Mac or administrator access.
- Gatekeeper warnings on unsigned or ad-hoc-signed builds. Signed and notarized builds are on the roadmap.
- Anything in the original Electron app: report it upstream.

## Design rules that keep Tessu safe

- System tools are started without a shell (`posix_spawn`), with fixed argument lists, a timeout, and
  their own process group so a cancel kills the whole tree. A model name that reaches a command line must
  match a strict pattern, and questions travel on stdin, never in arguments.
- The subscription integrations (Claude Code, Codex) run in an empty temporary folder with every tool
  switched off, hooks and user settings ignored, and Tessu refuses to ask if it cannot confirm that.
- Tessu never logs in to your router, never tries passwords and never changes settings on its own.
  AI agents can only answer and suggest steps; they cannot change anything themselves.
- The router-side HTTP client accepts only literal private IPv4 addresses, so nothing it does can leave the
  local network. Control URLs a router advertises are kept only if they point at the router itself.
- Everything sent to an AI passes through one whitelisting function (`PromptBuilder`); anything not copied
  there never leaves the Mac. Tests check that names, addresses and MACs are removed.
- Support messages are never sent by Tessu. The destination is injected at build time by whoever builds
  the app, from their own environment, and is absent from the source: a fork that builds from source has
  no destination. Reports go to a mail app or browser the user controls and approves.
