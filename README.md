# Dimly

Dimly is a free, open-source, lightweight macOS menu bar control center for multi-monitor setups. It gives you per-display brightness and reliable per-display on/off behavior, using true DDC control when available and overlay fallback when it is not, so mixed monitor fleets behave like one coherent setup.

<p align="center">
  <img src="https://img.shields.io/badge/macOS-native-000000?style=flat&logo=apple" alt="macOS native">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
</p>

<p align="center">
    <a href="https://github.com/Punshnut/macos-dimly/releases/latest">
    <img src="https://img.shields.io/badge/Download-latest-blueviolet?style=for-the-badge" alt="Download latest">
  </a>
</p>

<p align="center">
  <img src="Media/Dimly_Logo.png" alt="Dimly logo" height="200">
</p>

<div align="center">
  <details>
    <summary>🌍 Localizations (40)</summary>
    <p><strong>Europe</strong>: 🇪🇸 Español · 🇮🇹 Italiano · 🇩🇪 Deutsch · 🇫🇷 Français · 🇵🇹 Português · 🇺🇦 Українська · 🇷🇺 Русский · 🇵🇱 Polski · 🇬🇷 Ελληνικά · 🇳🇱 Nederlands · 🇸🇪 Svenska · 🇨🇿 Čeština · 🇭🇺 Magyar · 🇫🇮 Suomi · 🇮🇪 Gaeilge · 🇦🇩 Català.</p>
    <p><strong>Asia</strong>: 🇵🇭 Filipino · 🇮🇳 हिन्दी · 🇮🇩 Bahasa Indonesia · 🇻🇳 Tiếng Việt · 🇹🇷 Türkçe · 🇨🇳 中文 · 🇯🇵 日本語 · 🇰🇷 한국어 · 🇹🇭 ภาษาไทย · 🇸🇦 العربية · 🇧🇩 বাংলা · 🇮🇷 فارسی · 🇲🇾 Bahasa Melayu · 🇲🇲 မြန်မာ · 🇮🇳 தமிழ் · 🇮🇳 తెలుగు · 🇵🇰 اردو.</p>
    <p><strong>Africa</strong>: 🇪🇹 አማርኛ · 🇳🇬 Hausa · 🇰🇪 Kiswahili · 🇳🇬 Yorùbá.</p>
    <p><strong>Americas</strong>: 🇧🇷 Português (Brasil) · 🇲🇽 Español (LatAm) · 🇺🇸 English.</p>
  </details>
</div>

## Big hits

- **True per-display control** - Brightness, blackout, sleep, wake, rename, and copy ID per monitor from one menu.
- **DDC first, overlay fallback** - Hardware brightness and sleep/wake when possible; smooth fallback when DDC is unavailable.
- **Instant blackout + safe recovery** - Fast glare kill plus fixed panic hotkey to restore all displays.
- **Profiles + smart buttons** - Save monitor states, reorder profiles, and pin up to 4 smart profile buttons per row.
- **Profile automation** - Auto-apply a selected profile when external displays connect.
- **Targeted shortcuts** - Global hotkeys for all externals or specific displays.
- **Visibility controls** - Show display numbers, merge internal/external ordering, and hide selected monitors from the menu list.
- **Flexible interface** - Simple/advanced mode, appearance options (system/light/dark), and optional colorless smart buttons.
- **Backup and restore** - Import/export general settings and monitor settings independently.
- **Stealth mode** - Hide Dock and menu bar icon while keeping hotkeys active.
- **Universal + updates** - Intel/Apple Silicon builds with Sparkle updates through GitHub.

<p align="center">
  <a href="Media/Screenshots/Dimly_Simple_Minimized.png">
    <img src="Media/Screenshots/Dimly_Simple_Minimized.png" alt="Dimly screenshot" width="420">
  </a>
  <br>
  <sub>Screenshot: Simple mode</sub>
</p>

## What it actually does

- **Display inventory + tracking** - live monitor list, reconnect handling, and stable per-display identity.
- **Brightness pipeline** - DDC brightness where supported, overlay brightness where not.
- **Power controls** - DDC standby/wake with immediate blackout fallback when unsupported.
- **State persistence** - blackout and profile state survives monitor reconnects.
- **Hotkey system** - fixed panic hotkey plus customizable targeted bindings.
- **Profiles workflow** - save, apply, rename, reorder, and optional smart-button surfacing in Quick Actions.
- **Automation** - optional profile auto-apply when external monitors connect.
- **Settings backup** - selective import/export for general app settings and monitor-specific settings.
- **Diagnostics** - copy display report and open local diagnostics log quickly.
- **App behavior controls** - launch at login, hide Dock icon, hide menu icon, and keep running for shortcuts.

## How it works

1. Dimly sits in your menu bar. Click it or hit your hotkey.
2. Open a display tile and set **Brightness** per display.
3. If the monitor supports DDC/CI, Dimly uses true hardware brightness and standby/wake.
4. If it does not support DDC/CI, Dimly automatically uses **Overlay mode** for brightness and blackout fallback for on/off behavior.
5. Dimly tracks display changes, keeps state consistent, and can show numbered overlays for quick identification.

## Why this exists

I’ve worked on desks with 8-12 mixed monitors and uneven DDC support, where fast control matters more than perfect hardware. Dimly is built so every screen stays controllable in one clean flow.

## Keyboard & mouse

- **Show/hide Dimly menu popup:** default `Cmd` + `Ctrl` + `Option` + `M` (falls back to normal application window when menu bar icon is hidden).
- **Set your own hotkeys:** assign bindings for blackout, sleep/wake, or menu toggle for all externals or specific displays.
- **Option-click icon:** toggle blackout overlay on all externals.
- **Control-click icon:** toggle sleep/wake (with blackout fallback).
- **Restore everything:** fixed panic hotkey `Ctrl` + `Option` + `Shift` + `P`.
- **Per-display actions:** brightness, sleep, wake, blackout, rename, and copy IDs from each display row.
- **Close quickly:** press Esc or click away; the menu bar extra behaves like built-in menus.

## Quick tips

- Turn on **Show Display Numbers** when rearranging or labeling screens.
- Rename displays once so menus show friendly names instead of model strings.
- Use per-display **Brightness** first, then sleep/wake only when you actually want displays off.
- In mixed monitor setups, expect a blend of DDC and overlay mode; this is exactly what Dimly is designed for.
- If DDC/CI is supported, prefer **Sleep** for true power-off; otherwise blackout remains instant and reliable.
- Use **Profiles** + **Show as smart button** to pin your most-used monitor setups into Quick Actions.
- Use **Settings backup** before major changes so you can import just general or monitor settings later.
- Hide the menu bar icon if you want a stealth setup; hotkeys keep working.
- Use **Copy Display Report** or **Open Diagnostics Log** for fast support/debugging.

## DDC/CI and external monitors

**What is DDC/CI and what does Dimly do with it?**

DDC/CI (Display Data Channel Command Interface) is the protocol Dimly uses to send hardware brightness and sleep/wake commands to external monitors over the display cable. When it works, the monitor's actual hardware brightness changes. When it doesn't, Dimly automatically falls back to **overlay mode**, which dims the screen visually without touching hardware. Both modes are fully functional - DDC is just better when available.

Whether DDC works depends on three things in combination: your **Mac architecture**, the **cable and connection type**, and the **monitor itself**. The sections below cover each.

</details>

---

<details>
<summary><strong>Apple Silicon Macs (M1, M2, M3, M4 and later)</strong></summary>
<br>

Apple Silicon replaced the old IOFramebuffer display stack with a new DCP (Display Controller Processor) architecture. The legacy IOKit I2C APIs that Intel-era apps rely on do not function on M-series hardware - they silently fail at the driver level, causing DDC to appear unsupported for all external monitors.

**Dimly 1.5+ uses the correct Apple Silicon DDC path** via `IOAVService` APIs (the same approach used by MonitorControl, Lunar, m1ddc, and BetterDisplay). DDC now works on M-series Macs - but only with compatible connection types.

**Apple Silicon DDC checklist:**

- Use **USB-C with DisplayPort Alt Mode** or a direct **Thunderbolt cable** to the monitor. This is the highest-reliability connection on M-series Macs.
- **HDMI does not support DDC on Apple Silicon.** This is a hardware limitation of Apple's HDMI port on all M-series Macs and Mac mini (2018+). Switching from HDMI to USB-C/DisplayPort will fix DDC.
- Mini DisplayPort via a Thunderbolt adapter also works on most monitors.
- If you upgraded from an older Dimly build and DDC suddenly works - this is why.

</details>

---

<details>
<summary><strong>Intel Macs</strong></summary>
<br>

The traditional IOKit I2C path used on Intel Macs is well-established and stable. DDC generally works over DisplayPort, DVI, and most HDMI connections on Intel hardware.

If DDC doesn't work on your Intel Mac, the most common causes are:
- A dock, hub, or KVM sitting between the Mac and monitor (see the docks section below).
- DDC/CI disabled in the monitor's OSD menu.
- A cheap passive adapter that doesn't pass DDC through.

</details>

---

<details>
<summary><strong>Dell monitors</strong></summary>
<br>

Dell monitors support DDC/CI but **require it to be enabled in the OSD menu** - it is off by default on most models and may have been reset after a firmware update.

**How to enable DDC/CI on a Dell monitor:**
1. Press the physical menu button on the monitor.
2. Navigate to **Other Settings** (some models label it **Menu → Others**).
3. Find **DDC/CI** and set it to **Enable**.
4. Exit the OSD. Dimly will re-probe within a few seconds and show DDC as supported.

**Dell series breakdown:**

| Series | DDC on macOS | Notes |
|---|---|---|
| U-series (U2422H, U2720Q, U2723QE…) | Yes | Works via DisplayPort and USB-C. Best option for DDC. |
| P-series (P2422HE, P2415Q…) | Unlikely | Dell's own display manager lists no DDC/CI support on macOS for P-series. Overlay mode will be used. |
| S-series (S2421H…) | Inconsistent | Varies by model and firmware. Dimly detects and falls back as needed. |

**Additional Dell notes:**
- DDC/CI is not available over USB (the upstream USB-B port on the monitor). Always use the video cable (USB-C, DisplayPort, or HDMI) for DDC.
- Some Dell monitors accept DDC write commands but reject values outside a narrow range (e.g. refusing contrast below their OSD minimum). Dimly sends standard VCP commands; if those are rejected, the monitor falls back to overlay.
- Connecting via a Dell DisplayLink dock (D6000, D1000, WD22TB, UD22…) disables DDC - see the docks section.

</details>

---

<details>
<summary><strong>Docks, KVMs, and adapters</strong></summary>
<br>

DDC/CI breaks in most signal-passthrough scenarios. This is not a Dimly limitation - the dock or hub strips DDC before it reaches macOS.

| Device type | DDC? | Details |
|---|---|---|
| DisplayLink dock (Dell D6000, D1000, WD22TB, UD22…) | No | DisplayLink does not pass DDC on macOS at all. |
| MST hub (DisplayPort daisy-chain) | No | Multi-Stream Transport breaks DDC for all downstream monitors. |
| KVM switch | Usually no | Most KVMs strip DDC. Some enterprise KVMs preserve it - check the spec sheet. |
| Thunderbolt dock with direct DP output (not MST) | Usually yes | Look for "DDC passthrough" in the dock's specs. CalDigit, OWC, and Belkin docks generally pass DDC. |
| Simple passive USB-C → DP / USB-C → HDMI adapter | Usually yes | Works unless the adapter is low-quality and cuts corners on the AUX channel. |
| Active USB-C → HDMI adapter on Apple Silicon | No | HDMI on Apple Silicon carries no DDC regardless of adapter quality. |

**If you use a dock:** the fastest fix is a direct cable from Mac to monitor while testing. If DDC appears in Dimly with a direct cable but not through the dock, the dock is the cause.

</details>

---

<details>
<summary><strong>Other monitors and brands</strong></summary>
<br>

DDC/CI behaviour varies widely across brands. Common patterns:

- **LG UltraFine (Thunderbolt models)**: Use Apple's proprietary brightness protocol, not standard DDC/CI. Dimly uses overlay mode for these.
- **LG standard monitors** (27UK850, 27GP950…): DDC/CI generally works well on both Intel and Apple Silicon via DisplayPort/USB-C.
- **Samsung**: DDC/CI support varies by model. Most mid-range and high-end panels support it; budget panels often don't.
- **BenQ / ViewSonic**: Generally good DDC/CI support. Enable it in OSD if not working.
- **ASUS ProArt / ROG**: Good support on DisplayPort. Some models require DDC/CI to be enabled in OSD.
- **Monitors marketed as "USB-C monitors"**: Usually work well on Apple Silicon via their USB-C input; DDC/CI is typically enabled by default.

If your monitor isn't listed, try enabling DDC/CI in the OSD first, then try a direct DisplayPort or USB-C connection. If it still shows Overlay mode, DDC may simply not be supported on that model - overlay mode will work fine.

</details>

---

<details>
<summary><strong>Reading Dimly's DDC status indicators</strong></summary>
<br>

Each display row shows its current control mode:

| Status shown | Meaning |
|---|---|
| **DDC** | Hardware control active. Brightness and sleep/wake go to the monitor directly. |
| **Checking DDC** | Dimly is still probing - normal for a few seconds after connecting, waking, or launching. |
| **Overlay mode** | DDC unavailable. Brightness uses a screen overlay; blackout is used for sleep/wake. |

If a display stays on Overlay mode and you expected DDC:
1. Check the cable type (HDMI on Apple Silicon → switch to USB-C/DP).
2. Enable DDC/CI in the monitor's OSD menu.
3. Try a direct cable, bypassing any dock or hub.
4. Reconnect the monitor - Dimly re-probes on every reconnect and system wake.

Overlay mode is full-featured and reliable. It's not a degraded state - just software rather than hardware control.

</details>

---

## Updates, signing, and safety

- Updates are delivered via Sparkle with ed25519 signatures; the feed lives in `Resources/Info.plist`.
- If signature verification fails, Dimly offers a GitHub download fallback.
- Notarization and hardened runtime are part of the release scripts; binaries ship notarized.
- No telemetry, no background daemons; Dimly runs only in the menu bar or at login.

## Get Dimly

- <a href=”https://github.com/Punshnut/macos-dimly/releases/latest”>Download the latest release</a> and run it from `/Applications`.
- To auto-start, enable “Launch at Login” in Settings.

Supports Intel and Apple Silicon Macs. Requires macOS 14+

> **macOS 26.4 (Tahoe) users:** Dimly 1.4 includes visual fixes for macOS 26.4. If you are on 1.3, update to 1.4 before or immediately after upgrading to macOS 26.4 - otherwise the UI may look off. Sparkle auto-update will offer 1.4 automatically, or grab it manually from the [releases page](https://github.com/Punshnut/macos-dimly/releases/latest).

## Roadmap

- **Adaptive dimming** - remember per-location or time-of-day preferences.
- **Profile actions** - apply brightness + blackout/sleep rules when a saved setup is selected.
- **Per-app triggers** - auto-dim when select apps enter full screen.
- **Script hooks** - call custom scripts before/after blackout.

[Donate (Ko-Fi)](https://ko-fi.com/janfeuerbacher)

Made with ❤️

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Punshnut/macos-dimly&type=date&legend=top-left)](https://www.star-history.com/#Punshnut/macos-dimly&type=date&legend=top-left)
