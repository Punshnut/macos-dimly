# Dimly

Dimly is a free and open-source quiet macOS menu bar control center for multi-monitor setups. Its core feature is per-display brightness and per-display on/off control, with true DDC brightness when available and overlay mode fallback when it is not, so mixed premium, older, and cheap screens all behave like one coherent setup.

<p align="center">
  <img src="https://img.shields.io/badge/macOS-native-000000?style=flat&logo=apple" alt="macOS native">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
</p>

<p align="center">
    <a href="https://github.com/Punshnut/macos-dimly/releases/latest">
    <img src="https://img.shields.io/badge/Download-1.2-blueviolet?style=for-the-badge" alt="Download 1.2">
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

<p align="center">
  <details>
    <summary>Show screenshot (new screenshot when v1.3 gets released)</summary>
    <img src="Media/ScreenshotMenuBarWindow.png" alt="Dimly screenshot" width="600">
  </details>
</p>

## Big hits

- **Per-display brightness for real-world monitor fleets** - Control brightness per display with DDC when supported, and automatic overlay mode when not.
- **Per-display on/off switch** - Put each display to sleep/wake with DDC, with blackout fallback so it still behaves like a reliable on/off control.
- **Instant blackout** - Smash glare on any external display with a full-screen overlay.
- **Sleep & wake** - Send DDC/CI standby and wake when supported, with seamless blackout fallback.
- **Per-display control** - Brightness, toggle, sleep, wake, rename, and copy IDs per screen from one menu.
- **Display labels** - Pop numbered overlays on every screen so you always know which is which.
- **Shortcut friendly** - Global hotkeys, including a fixed panic shortcut to restore everything.
- **State that sticks** - Remembers active blackouts and re-applies them after reconnects.
- **Profiles** - Save snapshots and auto-apply when external monitors appear.
- **Stealth mode** - Hide menu bar + Dock icons; Dimly keeps working for hotkeys.
- **Simple ↔︎ advanced view** - Switch between a compact control surface and the full toolkit (and it sticks).
- **Per-display override** - Force blackout-only behavior even on DDC-capable monitors.
- **Animation control** - Optional fade in/out on sleep, wake, and restore.
- **Universal + updates** - Intel/Apple Silicon builds with Sparkle updates and a GitHub fallback.

## What it actually does

- **Display inventory + change tracking** - live list of displays with connect/disconnect logging.
- **Per-display brightness pipeline** - uses DDC brightness where possible and switches to overlay mode where DDC is unavailable.
- **Blackout overlays** - per-display fullscreen overlays with fade transitions and persistence.
- **DDC/CI power control** - probe support, send standby/wake commands, and track status.
- **Sleep/wake fallback** - if DDC fails or is unsupported, blackout takes over instantly so each display still has an effective on/off path.
- **Hotkey system** - register custom hotkeys plus a fixed panic hotkey.
- **Display labels** - numeric overlays with friendly names for each screen.
- **Profiles + automation** - save/apply display snapshots, auto-apply on external connect.
- **Menu bar actions** - quick actions, per-display menus, rename display, copy display IDs.
- **Suspend All indicator** - button fills when all externals are suspended and shows a colored border for partial suspension.
- **Display ordering** - drag to reorder external displays in the menu list.
- **Targeted hotkeys** - multiple bindings with per-display targets (not just “all externals”).
- **Diagnostics** - copy a display report and open a local diagnostics log.
- **Login + stealth** - launch at login, hide Dock icon, keep running when menu icon is hidden.
- **Updates + fallback** - Sparkle auto-updates with a GitHub download prompt on verify errors.

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
- **Set your own toggle:** assign a hotkey for Toggle External Blackout / Sleep-Wake in Settings.
- **Option-click icon:** toggle blackout overlay on all externals.
- **Control-click icon:** toggle sleep/wake (with blackout fallback).
- **Restore everything:** fixed panic hotkey `Ctrl` + `Option` + `Shift` + `P`.
- **Per-display actions:** brightness, sleep, wake, blackout, rename, and copy IDs from each display row.
- **Close quickly:** press Esc or click away-the menu bar extra behaves like built-in menus.

## Quick tips

- Turn on **Show Display Numbers** when rearranging or labeling screens.
- Rename displays once so menus show friendly names instead of model strings.
- Use per-display **Brightness** first, then sleep/wake only when you actually want displays off.
- In mixed monitor setups, expect a blend of DDC and overlay mode-this is exactly what Dimly is designed for.
- If DDC/CI is supported, prefer **Sleep** for true power-off; otherwise blackout remains instant and reliable.
- Hide the menu bar icon if you want a stealth setup-hotkeys keep working.
- Use **Copy Display Report** or **Open Diagnostics Log** for fast support/debugging.

## Updates, signing, and safety

- Updates are delivered via Sparkle with ed25519 signatures; the feed lives in `Resources/Info.plist`.
- If signature verification fails, Dimly offers a GitHub download fallback.
- Notarization and hardened runtime are part of the release scripts; binaries ship notarized.
- No telemetry, no background daemons-Dimly runs only in the menu bar or at login.

## Get Dimly

- <a href="https://github.com/Punshnut/macos-dimly/releases/latest">Download the latest release</a> and run it from `/Applications`.
- To auto-start, enable “Launch at Login” in Settings.

Supports Intel and Apple Silicon Macs. Requires macOS 14+

## Roadmap

- **Adaptive dimming** - remember per-location or time-of-day preferences.
- **Profile actions** - apply brightness + blackout/sleep rules when a saved setup is selected.
- **Per-app triggers** - auto-dim when select apps enter full screen.
- **Script hooks** - call custom scripts before/after blackout.

[Donate (Ko-Fi)](https://ko-fi.com/janfeuerbacher)

Made with ❤️

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Punshnut/macos-dimly&type=date&legend=top-left)](https://www.star-history.com/#Punshnut/macos-dimly&type=date&legend=top-left)
