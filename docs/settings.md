# Settings & Customization

This guide covers all the options available in Dimly's Settings window (Settings → open from the panel or press `Cmd` + `,`).

---

## General

### Launch at Login

Enable this to start Dimly automatically every time you log in. Recommended if you rely on hotkeys or scheduled profiles.

### Show menu bar icon

When enabled (default), the Dimly icon is visible in the menu bar. You can hide it for a cleaner menu bar - Dimly keeps running in the background and all hotkeys remain active. Open the panel by pressing your toggle hotkey.

### Hide Dock icon

Hides Dimly from the Dock and the App Switcher (`Cmd` + `Tab`). Useful for keeping Dimly out of sight while it runs quietly in the background.

Enabling both **Hide menu bar icon** and **Hide Dock icon** puts Dimly into Stealth Mode - fully hidden, only accessible via hotkeys.

### Quick Actions visibility

Controls when the **Quick Actions** section appears in the panel:

| Option | Behavior |
|---|---|
| Hide in compact | Quick Actions only appear in Simple and Advanced mode |
| Only in advanced | Quick Actions only appear in Advanced mode |
| Show on every screen | Quick Actions always visible in all panel modes |

### Settings Backup

Back up or restore your Dimly settings at any time.

**Two categories are exported/imported independently:**

- **General settings** - app behavior, hotkeys, and interface options
- **Monitor settings** - display names, ordering, and per-monitor options

To export: check the categories you want, then click **Export**. Dimly saves a `.dimly` backup file.

To import: check the categories you want to restore, click **Import**, then choose the backup file. Only the selected categories are overwritten - the rest stay unchanged.

Back up before making major changes so you can restore your settings if needed.

---

## Displays

The Displays tab lists all currently connected monitors and any previously seen monitors.

### Per-display options

For each connected display you can:

- **Rename** - give the display a friendly name (e.g., "Left Monitor", "TV")
- **Show in Dimly** - toggle whether this monitor appears in the panel's display list
- **Overlay Only (Never Sleep)** - force this display to always use overlay mode, never hardware sleep
- **Standby / Wake** - put the display to sleep or wake it directly from Settings

### Previously Seen Monitors

Dimly remembers monitors for 90 days after they were last connected. Previously seen monitors appear in this section with the date they were last seen.

Click **Forget** to remove a monitor's saved name, preferences, and brightness history. If it reconnects later, it starts fresh with default settings.

---

## LUTs

See the dedicated [LUT Library](luts.md) guide for importing, assigning, and backing up LUTs.

---

## Visuals

### Appearance

Choose how Dimly's panel looks:

| Option | Behavior |
|---|---|
| Like system | Follows macOS's current appearance (light or dark) |
| Always light | Forces the light theme |
| Always dark | Forces the dark theme |

### Transitions

**Fade out on sleep/blackout** - adds a smooth fade when a display goes to sleep or gets blacked out.

**Fade in on wake/restore** - adds a smooth fade when a display wakes or comes back from blackout.

**Transition speed** - controls how fast brightness changes and profile applies animate:

| Speed | Feel |
|---|---|
| Instant | No animation |
| Fast | Quick fade |
| Balanced | Default, natural feel |
| Smooth | Slower, more relaxed |
| Cinematic | Very slow, dramatic fade |

### Smart Buttons

**Smart buttons** - turn Smart Buttons on or off globally. When off, no profile quick-access buttons appear in the panel.

**Limit** - the maximum number of Smart Buttons shown (default 8). Adjustable if you want to limit clutter.

**Colorless mode** - removes individual colors from Smart Buttons and shows them in a neutral style.

To set colors for individual buttons, go to Settings → Profiles and click the color swatch next to each profile that has **Show as smart button** enabled.

---

## Shortcuts

See the dedicated [Shortcuts & Hotkeys](shortcuts.md) guide for full details.

---

## Profiles

See the dedicated [Profiles & Smart Buttons](profiles.md) guide for full details.

---

## Schedule

See the dedicated [Scheduling](scheduling.md) guide for full details.

---

## About

The About tab shows the current version number and links to:

- The GitHub repository (source code, changelog, and releases)
- Bug report and feedback submission
- Donation link (Ko-Fi)

Use **Check for Updates** (in the App section of the panel) to check if a newer version is available. Updates are delivered via Sparkle with signed binaries.
