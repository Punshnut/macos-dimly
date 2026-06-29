# Dimly

Dimly is a free, open-source macOS menu bar app for multi-monitor brightness and display control. It uses true DDC/CI hardware control when available, and automatically falls back to overlay mode when it isn't - so every display in a mixed setup stays controllable from one place.

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

---

## Features

- **Per-display brightness** — hardware DDC control or smooth overlay fallback, per monitor
- **Contrast** — hardware DDC contrast control for external monitors
- **Sleep, wake, and blackout** — instant blackout overlay plus true DDC standby when supported
- **Color profiles** — switch ICC profiles per external display: sRGB, Display P3, DCI-P3, Adobe RGB, BT.709, BT.2020, Extended P3, HDR (BT.2100 PQ/HLG), creative effects, and user-installed calibrations
- **Appearance filters** — per-display gamma filters: Invert, Warm, Cool
- **Night Shift** — toggle and warmth control integrated directly in the display panel
- **True Tone** — per-display True Tone toggle for supported hardware
- **Resolution & refresh rate** — switch display modes and Hz per external monitor
- **Input source** — switch between HDMI, DisplayPort, DVI, and VGA inputs via DDC
- **Profiles** — save and apply named display setups in one click; pin them as Smart Buttons in the menu bar
- **Schedule** — auto-apply profiles at fixed times or at sunrise/sunset based on your location
- **Global hotkeys** — assign keyboard shortcuts per display or for all externals at once
- **Profile automation** — auto-apply a profile when a specific external display connects
- **Stealth mode** — hide the menu bar icon and Dock entry; hotkeys keep working
- **Backup and restore** — export and import general settings and monitor settings independently
- **Panic hotkey** — `Ctrl` + `Option` + `Shift` + `P` always restores all displays, no matter what

<p align="center">
  <a href="Media/Screenshots/Dimly_Simple_Minimized.png">
    <img src="Media/Screenshots/Dimly_Simple_Minimized.png" alt="Dimly screenshot" width="420">
  </a>
  <br>
  <sub>Screenshot: Simple mode</sub>
</p>

## How it works

1. Dimly sits in the menu bar. Click it to open the panel.
2. Expand a display tile and drag the **Brightness** slider.
3. If the monitor supports DDC/CI, brightness and sleep/wake go directly to the hardware.
4. If not, Dimly uses **Overlay mode** - a transparent dimming layer that works on every display.
5. Save your current setup as a **Profile** to restore it anytime, automatically, or on a schedule.

## DDC/CI and external monitors

DDC/CI is the protocol Dimly uses to send hardware brightness and standby commands over the display cable. When it works, the monitor's actual hardware brightness changes. When it doesn't, Dimly falls back to overlay mode automatically. Both are fully functional - DDC is just better when available.

Whether DDC works depends on your **Mac architecture**, **cable type**, and the **monitor itself**.

<details>
<summary><strong>Apple Silicon Macs (M1, M2, M3, M4 and later)</strong></summary>
<br>

Apple Silicon uses a new DCP display stack. Legacy IOKit I2C APIs silently fail on M-series hardware, so Dimly uses `IOAVService` APIs instead - the same approach as MonitorControl, Lunar, and BetterDisplay.

**DDC works on Apple Silicon, but only with compatible connections:**

- **USB-C (DisplayPort Alt Mode)** or **Thunderbolt** - highest reliability
- **HDMI does not carry DDC on Apple Silicon** - a hardware limitation on all M-series Macs and Mac mini (2018+). Switch to USB-C/DisplayPort to get DDC.
- Mini DisplayPort via Thunderbolt adapter also works on most monitors.

</details>

---

<details>
<summary><strong>Intel Macs</strong></summary>
<br>

The IOKit I2C path on Intel is stable. DDC works over DisplayPort, DVI, and most HDMI connections.

Common reasons it doesn't work:
- A dock, hub, or KVM between the Mac and monitor (see below)
- DDC/CI disabled in the monitor's OSD menu
- A cheap passive adapter that doesn't pass DDC through

</details>

---

<details>
<summary><strong>Dell monitors</strong></summary>
<br>

Dell requires DDC/CI to be **enabled in the OSD** - it's off by default and may reset after a firmware update.

**To enable:** physical menu button → **Other Settings** (or **Menu → Others**) → **DDC/CI** → **Enable** → exit OSD. Dimly re-probes within seconds.

| Series | DDC on macOS | Notes |
|---|---|---|
| U-series (U2422H, U2720Q, U2723QE…) | Yes | Works via DisplayPort and USB-C. |
| P-series (P2422HE, P2415Q…) | Unlikely | No DDC/CI support on macOS per Dell's own docs. |
| S-series (S2421H…) | Inconsistent | Varies by model and firmware. |

DDC is not available over the USB-B upstream port - always use the video cable. DisplayLink docks (D6000, D1000, WD22TB…) also break DDC.

</details>

---

<details>
<summary><strong>Docks, KVMs, and adapters</strong></summary>
<br>

Most docks strip DDC before it reaches macOS. This is not a Dimly limitation.

| Device | DDC? | Notes |
|---|---|---|
| DisplayLink dock | No | DDC not passed on macOS |
| MST hub (DP daisy-chain) | No | Breaks DDC for all downstream monitors |
| KVM switch | Usually no | Some enterprise KVMs preserve it - check specs |
| Thunderbolt dock (direct DP, not MST) | Usually yes | CalDigit, OWC, Belkin generally pass DDC |
| Passive USB-C → DP adapter | Usually yes | Fails only if adapter cuts corners on the AUX channel |
| USB-C → HDMI on Apple Silicon | No | HDMI carries no DDC on M-series regardless of adapter |

**Quick test:** connect directly to the Mac without a dock. If DDC appears, the dock is the cause.

</details>

---

<details>
<summary><strong>Other monitors and brands</strong></summary>
<br>

- **LG UltraFine (Thunderbolt)** - uses Apple's proprietary brightness protocol, not DDC/CI. Overlay mode is used.
- **LG standard monitors** (27UK850, 27GP950…) - DDC works well via DisplayPort/USB-C on Intel and Apple Silicon.
- **Samsung** - varies by model. Mid-range and up usually support DDC/CI; budget panels often don't.
- **BenQ / ViewSonic** - generally good support. Enable DDC/CI in OSD if not detected.
- **ASUS ProArt / ROG** - good on DisplayPort. Some models need DDC/CI enabled in OSD.
- **USB-C monitors** - usually work well on Apple Silicon via USB-C; DDC/CI typically enabled by default.

If your monitor isn't listed: enable DDC/CI in the OSD first, then try a direct DisplayPort or USB-C connection. If it still shows Overlay mode, the monitor likely doesn't support DDC/CI - overlay mode works fully regardless.

</details>

---

<details>
<summary><strong>DDC status indicators</strong></summary>
<br>

| Badge | Meaning |
|---|---|
| **DDC** | Hardware control active |
| **Checking DDC** | Probing in progress - normal for a few seconds after connect or wake |
| **Overlay mode** | DDC unavailable; software control in use |

If a display stays on Overlay mode: check the cable type, enable DDC/CI in the OSD, test without a dock, then reconnect. See [Troubleshooting](docs/troubleshooting.md) for a full diagnosis guide.

</details>

---

## Get Dimly

[Download the latest release](https://github.com/Punshnut/macos-dimly/releases/latest) and run it from `/Applications`. Enable **Launch at Login** in Settings to start it automatically.

Requires macOS 14+. Supports Intel and Apple Silicon.

> **macOS 26 (Tahoe) users:** update to Dimly 2026.5.1 before or right after upgrading - otherwise the UI may look off. Sparkle will offer it automatically, or grab it from the [releases page](https://github.com/Punshnut/macos-dimly/releases/latest).

## User Guide

Full documentation is in the [`docs/`](docs/README.md) folder: display controls, profiles, scheduling, shortcuts, settings, and troubleshooting.

## Roadmap

- **Adaptive dimming** - remember per-location or time-of-day preferences
- **Per-app triggers** - auto-dim when select apps enter full screen
- **Script hooks** - call custom scripts before/after blackout

[Donate (Ko-Fi)](https://ko-fi.com/janfeuerbacher)

Made with ❤️

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Punshnut/macos-dimly&type=date&legend=top-left)](https://www.star-history.com/#Punshnut/macos-dimly&type=date&legend=top-left)
