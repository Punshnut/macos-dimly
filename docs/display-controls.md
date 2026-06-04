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

Open a display tile to see its controls. From the tile you can:

- Set **Brightness** with the slider
- Put the display in **Standby** or **Wake** it
- Toggle **Blackout** on or off
- Rename the display (give it a friendly name like "Left Monitor")
- Copy the display's hardware ID to the clipboard

Right-click or use the tile's context menu for **Rename Display** and **Copy Display ID**.

---

## Overlay Only (Never Sleep)

If you want a display to always use overlay mode - even when DDC is available - enable **Overlay Only (Never Sleep)** in Settings → Displays for that monitor. This is useful when:

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

Long model strings like "DELL U2723QE" can be hard to tell apart in a multi-monitor setup. Use **Rename Display** to give each monitor a friendly name. The name persists across reconnects and is used everywhere in Dimly's interface.

To rename: expand the display tile → right-click or open the menu → **Rename Display**.

---

## Merging internal and external display order

By default, the internal display (your MacBook screen) appears separately. Enable **Merge internal and external monitor order** in Settings → General to arrange all displays - built-in and external - in one shared list. This lets you set a custom viewing order that matches your physical desk layout.
