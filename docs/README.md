# Dimly - User Guide

Dimly is a free macOS menu bar app for controlling brightness, sleep, and wake across all your external monitors. It uses hardware DDC control when your monitor supports it, and automatically falls back to a software overlay when it doesn't - so every display works, regardless of what cable you're using or how old the monitor is.

---

## Install and get started

1. [Download Dimly](https://github.com/Punshnut/macos-dimly/releases/latest) and move it to your Applications folder.
2. Launch Dimly. A display icon appears in your menu bar.
3. Click the icon to open the control panel.
4. Click a display tile to expand it, then drag the **Brightness** slider.
5. Go to **Settings → General** and enable **Launch at Login** so Dimly starts automatically.

That's the basics. Everything below explains what else Dimly can do.

---

## What Dimly can do

**Control any display**
Adjust brightness per monitor, put displays to sleep, wake them, or black them out instantly. Works on every external monitor - hardware control where possible, software overlay where not.

**Save setups as profiles**
Capture your current display state - brightness, power, order - as a named profile. Apply it in one click, pin it as a Smart Button in the menu bar, or have it apply automatically when a monitor connects.

**Schedule display changes**
Apply a profile at a fixed time each day, or relative to sunrise and sunset at your location. Useful for automatically dimming your monitors in the evening or brightening them in the morning.

**Control with keyboard shortcuts**
Assign global hotkeys to toggle blackout, sleep/wake, or open the panel - for all external displays at once or for a specific monitor. Works in any app.

**Run quietly in the background**
Hide the menu bar icon and Dock entry. Hotkeys and schedules keep working. Use the panic hotkey (`Ctrl` + `Option` + `Shift` + `P`) to restore all displays at any time.

---

## Key concepts

**DDC (hardware control)**
DDC/CI lets Dimly talk directly to your monitor over the display cable. When active, brightness is changed at the hardware level - just like using the monitor's physical buttons. Each display tile shows a green **DDC** badge when this is working.

**Overlay mode (software fallback)**
When DDC isn't available, Dimly places a transparent dimming layer over the screen. Brightness control still works; blackout is used instead of hardware sleep. The tile shows a blue **Overlay mode** badge. This is not a degraded state - it works fully on every display.

**Blackout**
An instant full-screen black overlay. Works on every monitor, always. Use it to block glare without putting the monitor to sleep, or to hide a screen quickly during a call.

**Profiles**
A saved snapshot of your display setup: brightness levels, power states, and arrangement. Apply a profile to switch between your desk, presentation, or night setup in one tap.

**Smart Buttons**
Profile shortcuts pinned directly in the menu bar panel's Quick Actions section. Each button has a color you pick and applies a profile in one tap.

**Panic hotkey**
`Ctrl` + `Option` + `Shift` + `P` - always restores all displays, no matter what. Fixed, always active, can't be removed.

---

## Common setups

**Multi-monitor desk**
Rename each display once (e.g. "Left", "Main", "TV") so the panel shows friendly names. Save a "Work" profile at your normal brightness, a "Focus" profile with side monitors blacked out, and a "Night" profile at low brightness. Pin them as Smart Buttons and switch between them in one click.

**MacBook + external monitor**
Use brightness control for the external display. Enable **Launch at Login** and set up auto-apply so your preferred profile loads whenever you plug in. Use `Option`-click on the menu bar icon to instantly black out the external when you step away.

**Presentation or meeting**
Save a "Presentation" profile with your external monitor at 100% and any unused monitors blacked out. Apply it before you start. Use the panic hotkey if anything goes wrong mid-presentation.

**Evening wind-down**
Set up a Schedule with a sunset trigger and a profile that dims all displays to 20–30%. Dimly applies it automatically - no action needed.

---

## Guide

| | |
|---|---|
| [Display Controls](display-controls.md) | Brightness, sleep, wake, blackout, DDC vs overlay, renaming |
| [Profiles & Smart Buttons](profiles.md) | Saving setups, quick-access buttons, auto-apply on connect |
| [Scheduling](scheduling.md) | Clock and sunrise/sunset triggers, location setup |
| [Shortcuts & Hotkeys](shortcuts.md) | Global hotkeys, panic recovery, custom bindings |
| [Settings & Customization](settings.md) | Appearance, transitions, display visibility, backup/restore |
| [Troubleshooting](troubleshooting.md) | DDC not working, monitor compatibility, diagnostics |

---

## Quick reference

| Action | How |
|---|---|
| Open/close panel | Click the menu bar icon |
| Toggle blackout on all externals | Option-click the icon |
| Toggle sleep/wake on all externals | Control-click the icon |
| Open panel from keyboard | `Cmd` + `Ctrl` + `Option` + `M` (default) |
| Restore all displays (panic) | `Ctrl` + `Option` + `Shift` + `P` |
| Close panel | `Esc` or click outside |
