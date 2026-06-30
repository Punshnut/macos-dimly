# Display Controls

This guide covers everything you can do with individual displays in Dimly: brightness, sleep, wake, and blackout.

---

## Opening the panel

Click the Dimly icon in the menu bar. The panel shows a tile for each connected display. Click a tile to expand it and reveal the controls.

You can also open the panel with a global hotkey. The default is `Cmd` + `Ctrl` + `Option` + `M`. You can change this in Settings → Shortcuts.

---

## Brightness

Drag the **Brightness** slider to set the level for that display. Use the **−** and **+** buttons for fine-grained adjustments.

Brightness works differently depending on what your monitor supports:

- **DDC supported** (green badge) - Dimly sends the brightness value directly to the monitor's hardware. The monitor's physical brightness changes, just as if you used its on-screen menu.
- **Overlay mode** (blue badge) - Dimly draws a transparent dimming layer over the screen. The image is visually darkened without touching monitor hardware. Fully functional, just software-based.

Dimly always tries DDC first. If the monitor doesn't support it, overlay mode kicks in automatically. You don't need to configure anything - it just works.

---

## Sleep and Wake

**Sleep** sends the monitor into standby - it turns the panel off and stops drawing power, just like closing a laptop lid.

- If DDC is supported, Dimly sends a hardware standby command. The monitor powers down completely.
- If DDC is not supported, Dimly shows a full-screen blackout overlay as a visual substitute. The monitor stays on electronically but the screen goes black.

**Wake** reverses a sleep or blackout state. Use the **Wake Externals** button in Quick Actions to bring all external displays back at once, or wake a single display from its tile.

**Emergency recovery:** If you accidentally black out or sleep all your displays, press the panic hotkey `Ctrl` + `Option` + `Shift` + `P` to restore everything instantly.

---

## Blackout

**Blackout** draws a full-screen black overlay on a display. It's immediate and works on every monitor regardless of DDC support.

Use blackout when you want to:
- Block glare from an unused screen without putting it to sleep
- Quickly hide a display during a meeting or presentation
- Darken a display while keeping it powered on and ready

To toggle blackout on all external displays at once, **Option-click** the Dimly menu bar icon. To toggle a single display, expand its tile and use the **Blackout Display** / **Restore Display** button.

Blackout vs. Sleep:
- **Blackout** is instant, software-only, and always available. The monitor stays on.
- **Sleep** (with DDC) fully powers down the panel. Takes a second or two for the monitor to respond.

---

## Quick Actions

The **Quick Actions** section at the top of the panel has one-tap buttons for common actions:

| Button | What it does |
|---|---|
| Toggle External Blackout | Blackout or restore all external displays |
| Sleep Externals | Send all external displays to sleep |
| Wake Externals | Wake all external displays |
| Panic: All On | Restore every display immediately |
| Show Display Numbers | Show numbered overlays on each screen |

**Show Display Numbers** puts a large number on each screen so you can quickly identify which display is which when renaming or rearranging.

---

## Controlling a specific display

Open a display tile in the menu bar panel or in Settings → Displays to see all controls. Each display card has collapsible sections - click a section header to expand or collapse it. Dimly remembers which sections are open per display.

---

## Contrast (DDC only)

The **Contrast** section appears for external displays with DDC support. Drag the slider or use the arrow buttons to adjust the monitor's hardware contrast level (0–100). This sends a DDC VCP command directly to the display - equivalent to using the monitor's physical on-screen menu.

Contrast and brightness interact differently on each monitor. Most monitors look best somewhere between 70–80% contrast. Adjust brightness first; only change contrast if you need deeper blacks or brighter whites.

---

## Power - Standby and Wake

**Standby** sends an external display into hardware sleep over DDC. **Wake** brings it back. These are the same operations as the Sleep/Wake buttons in the menu bar quick actions, surfaced here per-display in Settings.

---

## Image - Color, Night Shift, True Tone

The **Image** section groups colour-related controls.

### Color profiles (external displays)

Dimly can switch the active ICC colour profile for any external display. Colour profiles affect how the display interprets and renders colour - the right profile depends on your monitor's gamut and your workflow.

Profiles are organised into groups in the picker:

| Group | What it contains |
|---|---|
| **Standard** | System Default, sRGB, Display P3, DCI-P3, Adobe RGB, BT.709, BT.2020, ProPhoto RGB, ACES CG Linear, Generic RGB |
| **Modern** | Extended Display P3, Extended sRGB, sRGB Linear, BT.2100 PQ (HDR), BT.2100 HLG (HDR) |
| **Creative Effects** | Black & White, Blue Tone, Gray Tone, Sepia Tone, Lightness Decrease/Increase |
| **Display Calibration** | Monitor-specific ICC files generated by DisplayCAL, i1Profiler, or macOS's built-in calibrator |
| **User Installed** | Profiles you've placed in ~/Library/ColorSync/Profiles |

**System Default** resets the display to whatever macOS has assigned for that monitor - use it to undo any profile change.

For most sRGB monitors (most office and consumer displays): leave it on System Default or switch to **sRGB (Standard)**.
For wide-gamut monitors (most gaming and pro monitors shipped after 2018): try **Display P3** or **DCI-P3**.
For photography or print work: **Adobe RGB (1998)** or **ProPhoto RGB (ROMM)**.
For creative grayscale effects: the **Black & White** profile in Creative Effects.

**Note:** ICC profile switching uses a private macOS API (`CGDisplaySetColorProfile`). It works on most external displays but the change does not persist after macOS restarts or after the display reconnects - Dimly will reapply the saved profile automatically.

Built-in Mac displays (MacBook screen, iMac) do not support profile switching through this API. Use **System Settings → Displays → Color Profile** for those instead. Dimly shows a link to System Settings in the Image section for built-in displays.

### Appearance filters

Gamma-table filters applied directly by Dimly. Unlike colour profiles, these are software overlays that re-map how intensities are rendered per-channel:

| Filter | Effect |
|---|---|
| **Standard** | No filter (default) |
| **Inverted** | Inverts all channels - useful for reducing eye strain in dark environments |
| **Warm** | Reduces blue channel slightly - shifts the white point warmer without Night Shift |
| **Cool** | Reduces red channel slightly - shifts the white point cooler/bluer |

Filters work on all displays including built-in. They reset on sleep/wake - Dimly restores them automatically on wake.

### LUTs

A **LUT (Look-Up Table)** remaps the color output of a display using a calibration or creative curve. LUTs are applied at the gamma-table level - they affect the full display output, just like Appearance Filters.

Supported formats: `.cube` (Resolve, Premiere, Photoshop), `.3dl` (Autodesk/Flame), `.lut` (Resolve 1D exports), `.csv` (spreadsheet-style 1D tables).

**To assign a LUT to a display:**
1. Go to **Settings → LUTs** and import a LUT file.
2. In **Settings → Displays**, expand a display's **Image** section.
3. Choose a LUT from the **LUT** picker. Select **None** to remove it.

**1D vs 3D LUTs:**
- **1D LUTs** remap each channel independently. These map exactly to the gamma table.
- **3D LUTs** apply full cross-channel color transforms. Dimly samples the neutral axis of 3D LUTs to derive per-channel curves - this works well for calibration LUTs but may not fully reproduce strong creative color grading effects.

LUTs are reapplied automatically after sleep/wake and display reconnects. They compose with Appearance Filters - the filter is applied first, then the LUT curve.

### Night Shift

Night Shift reduces blue light by shifting the display's white point towards amber after sunset. Dimly's Night Shift toggle and warmth slider control the **system-wide** Night Shift setting - the same one in System Settings → Displays → Night Shift. Changes apply to all displays at once.

The Night Shift toggle appears on the built-in display card only (since it is system-global). The warmth slider appears when Night Shift is on.

Night Shift is not available on all Macs. If the card does not show Night Shift, the current hardware doesn't support it.

### True Tone

True Tone automatically adjusts the display's white balance based on ambient lighting. The True Tone toggle appears on display cards where the feature is supported. On unsupported displays the control is hidden.

---

## Resolution and Refresh Rate (external displays)

The **Resolution** section lists all modes reported by the display. Two pickers appear:

- **Resolution** - the logical output size, e.g. "2560×1440" or "1920×1080 HiDPI"
- **Refresh Rate** - the available Hz options for the selected resolution

Changes take effect immediately and are saved so Dimly can reapply them the next time the display connects.

HiDPI entries (Retina-equivalent) are listed separately from native-pixel modes. For most external displays, the HiDPI "2x" mode at half the native resolution gives the sharpest result.

---

## Input Source (DDC only)

For external DDC monitors, the **Input Source** section lets you switch which physical port the display uses. Available sources:

| Option | Connector |
|---|---|
| HDMI 1 / HDMI 2 | HDMI ports |
| DisplayPort 1 / DisplayPort 2 | DisplayPort ports |
| VGA 1 / VGA 2 | VGA ports (legacy) |
| DVI 1 / DVI 2 | DVI ports (legacy) |
| Composite Video | Composite/Component (legacy) |

Not all monitors support input switching via DDC. If your monitor ignores the command, use its physical on-screen menu instead.

---

## Dimly Behavior

The **Dimly Behavior** section has controls for how this specific display appears in Dimly:

- **Show in Dimly** - hide a display from the menu bar panel and Settings while keeping it working. Useful for rarely-adjusted monitors.
- **Overlay Only** - forces software overlay mode even when DDC is available. Use when a monitor's DDC sleep/wake is unreliable.

---

## Overlay Only

If you want a display to always use overlay mode - even when DDC is available - enable **Overlay Only** in the Dimly Behavior section of that display's card. This is useful when:

- A monitor's DDC sleep/wake is unreliable or slow
- You prefer instant blackout behavior over hardware standby
- You're using a monitor where DDC wake is inconsistent

---

## DDC status indicators

Each display tile shows its current control mode:

| Badge | Meaning |
|---|---|
| **DDC** (green) | Hardware control is active |
| **Checking DDC** (orange) | Dimly is probing - normal for a few seconds after connecting or waking |
| **Overlay mode** (blue) | DDC unavailable; software control is in use |

If a display stays on Overlay mode and you expected DDC, see the [Troubleshooting](troubleshooting.md) guide.

---

## Renaming displays

Long model strings like "DELL U2723QE" can be hard to tell apart in a multi-monitor setup. Use **Rename** to give each monitor a friendly name. The name persists across reconnects and is used everywhere in Dimly's interface.

---

## Merging internal and external display order

By default, the internal display (your MacBook screen) appears separately. Enable **Merge internal and external monitor order** in Settings → General to arrange all displays - built-in and external - in one shared list. This lets you set a custom viewing order that matches your physical desk layout.
