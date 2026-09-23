# Troubleshooting

---

## DDC not working - display stays in Overlay mode

Dimly will always show **Overlay mode** when it cannot communicate with a monitor over DDC/CI. This is a fallback, not an error - brightness and blackout still work. But if you expected hardware control, here's how to diagnose it.

### Step 1: Check your cable type

This is the most common cause on Apple Silicon Macs.

**Apple Silicon (M1, M2, M3, M4 and later):**
- HDMI does not carry DDC on Apple Silicon. This is a hardware limitation of all M-series Macs. Switching from HDMI to USB-C or DisplayPort almost always fixes DDC.
- USB-C with DisplayPort Alt Mode and direct Thunderbolt cables have the best DDC support.
- Mini DisplayPort via a Thunderbolt adapter also works on most monitors.

**Intel Macs:**
- DDC works over DisplayPort, DVI, and most HDMI connections.
- If it stopped working, a dock or hub is usually the cause (see Step 3).

### Step 2: Enable DDC/CI in the monitor's OSD menu

Many monitors have DDC/CI disabled by default and need it switched on manually.

- **Dell monitors:** Press the physical menu button → navigate to **Other Settings** (or **Menu → Others**) → find **DDC/CI** → set it to **Enable**. Exit the OSD. Dimly will detect the change within a few seconds.
- **BenQ / ViewSonic / ASUS:** Look for a **DDC/CI** option in the monitor's System or Setup menu.
- **Other brands:** Check the manual or search "[monitor model] DDC/CI enable".

### Step 3: Try a direct cable (bypass the dock or hub)

Docks and hubs are the second most common cause of DDC failing:

| Device | DDC? |
|---|---|
| DisplayLink dock (Dell D6000, D1000, WD22TB, UD22…) | No - DisplayLink does not pass DDC on macOS |
| MST hub (DisplayPort daisy-chain) | No - MST breaks DDC for all downstream monitors |
| KVM switch | Usually no - most KVMs strip DDC |
| Thunderbolt dock with direct DP output | Usually yes - look for "DDC passthrough" in the spec sheet |
| Simple passive USB-C → DP or USB-C → HDMI adapter | Usually yes |

**Test:** connect the monitor directly to your Mac with a cable (no dock). If DDC appears in Dimly, the dock is the issue.

### Step 4: Reconnect or restart

- Disconnect and reconnect the monitor - Dimly re-probes DDC on every reconnect.
- If that doesn't help, try putting the Mac to sleep and waking it - DDC is also re-probed on wake.

---

## Monitor brand compatibility notes

**Dell:**
- U-series (U2422H, U2720Q, U2723QE…): good DDC support via DisplayPort and USB-C. Enable DDC/CI in OSD.
- P-series: limited DDC/CI support on macOS; expect Overlay mode.
- S-series: varies by model and firmware.

**LG UltraFine (Thunderbolt models):**
Thunderbolt UltraFine monitors use Apple's proprietary brightness protocol, not standard DDC/CI. Dimly uses Overlay mode for these. Brightness still works via the overlay.

**LG standard monitors** (27UK850, 27GP950…):
DDC/CI generally works well on both Intel and Apple Silicon via DisplayPort or USB-C.

**Samsung:**
Support varies by model. Mid-range and high-end panels usually support DDC/CI; budget panels often don't.

**BenQ / ViewSonic / ASUS ProArt / ROG:**
Generally good DDC/CI support. Enable it in the OSD if Dimly shows Overlay mode.

**USB-C monitors:**
Monitors marketed as "USB-C monitors" usually work well on Apple Silicon via their USB-C input - DDC/CI is typically enabled by default.

---

## Panel flickers or brightness jumps unexpectedly

If your Mac's automatic brightness (Ambient Light Sensor) is active, it can fight Dimly's brightness changes on external monitors. Check macOS System Settings → Displays and disable "Automatically adjust brightness" if this is happening.

---

## Displays not showing up in Dimly

- Make sure the monitor is connected and the cable is fully seated.
- Try disconnecting and reconnecting the display.
- Check **Settings → Displays** to see if the monitor is hidden. If **Show in Dimly** is off for that display, it won't appear in the panel.

---

## A previously-used monitor is missing from settings

Dimly remembers monitors for 90 days. If you reconnect a monitor after a long gap, or if you clicked **Forget** for it, it will appear as a new display and won't have its old saved name or settings.

To see monitors Dimly has seen recently, open **Settings → Displays → Previously Seen Monitors**.

---

## All displays went black and I can't see anything

Press the panic hotkey: **`Ctrl` + `Option` + `Shift` + `P`**

This restores all displays immediately. It works even when the panel is closed and even when the menu bar icon is hidden.

---

## Scheduled profiles aren't applying

- Check that **Enable Scheduling** is on in Settings → Schedule.
- Check that the individual schedule entry is enabled (the toggle next to it).
- For solar triggers, make sure your location is set correctly (Settings → Schedule → Location).
- Schedules catch up within a 5-minute window after wake. If you were away longer than that, the missed schedule won't be applied retroactively.

---

## Auto-apply profile isn't triggering

- Check that the trigger monitor matches the setting. If you selected a specific display, that exact monitor must be the one connecting.
- Try selecting **Any External Monitor** to see if the auto-apply works at all, then narrow down to a specific display.

---

## Getting diagnostic information

**Copy Display Report:** In the panel, open the App section → **Copy Display Report**. This copies a summary of all connected displays, their resolution, refresh rate, and DDC status to the clipboard. Paste it when reporting an issue.

**Open Diagnostics Log:** In the panel, open the App section → **Open Diagnostics Log**. This opens a local log file with detailed information about Dimly's recent activity. Useful for tracking down timing issues or unexpected behavior.

---

## macOS permission prompts

**Location (for solar scheduling):** macOS will ask for permission to access your location when you click **Use My Location** in Settings → Schedule. Grant it once. Dimly only reads location when you request it - not continuously.

**Accessibility (for global hotkeys):** Dimly needs Accessibility permission to register global hotkeys. macOS will prompt you on first launch or when you add your first hotkey. Go to System Settings → Privacy & Security → Accessibility → enable Dimly.
