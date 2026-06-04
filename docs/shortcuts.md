# Shortcuts & Hotkeys

Dimly supports global keyboard shortcuts so you can control your displays without opening the panel.

---

## Built-in menu bar interactions

These work by clicking the Dimly icon in the menu bar:

| Action | How |
|---|---|
| Open/close the panel | Click the icon |
| Toggle blackout on all external displays | Option-click the icon |
| Toggle sleep/wake on all external displays | Control-click the icon |
| Close the panel | Press `Esc` or click anywhere outside |

---

## Default global hotkey

**`Cmd` + `Ctrl` + `Option` + `M`** - Opens or closes the Dimly panel from anywhere, even when another app is in focus.

If the menu bar icon is hidden (Stealth Mode), this hotkey opens a regular app window instead.

You can change this binding in Settings → Shortcuts by editing the **Toggle Window** hotkey.

---

## Panic hotkey

**`Ctrl` + `Option` + `Shift` + `P`** - Restores all displays immediately.

This hotkey is fixed and always active. It cannot be changed or removed. Use it if you accidentally blackout or sleep all your displays and can't see the screen.

The panic hotkey works even when the Dimly panel is closed and even when the menu bar icon is hidden.

---

## Custom hotkeys

In **Settings → Shortcuts**, you can create custom global hotkeys for display actions.

**To add a hotkey:**

1. Click **Add Hotkey**.
2. Set the **Action**:
   - **Toggle Blackout** - blackout or restore a display
   - **Toggle Sleep/Wake** - sleep or wake a display
   - **Toggle Window** - open or close the Dimly panel
3. Set the **Display**:
   - **All External Displays** - the action applies to every external monitor at once
   - A specific display - the action targets only that monitor
4. Click **Change** to record your key binding. Press the key combination you want, then it's set.

You can add as many hotkeys as you need. Hotkeys are registered globally - they work even when Dimly is not the active app.

---

## Supported key types

Hotkeys support:

- Letter keys (A–Z)
- Number keys (0–9)
- Function keys (F1–F19)
- Arrow keys, Page Up/Down, Home, End
- Keypad keys
- Media keys: Volume Up/Down, Mute, Brightness Up/Down, Play/Pause, Next/Previous Track, Rewind, Fast Forward
- Keyboard brightness keys

---

## Managing existing hotkeys

- **Edit a binding:** Click **Change** next to the hotkey you want to update, then press the new key combination.
- **Delete a hotkey:** Click the delete button (trash icon) next to the hotkey entry.

---

## Hotkeys with hidden menu bar icon

If you hide the Dimly menu bar icon (Settings → General → Show menu bar icon), hotkeys keep working. You can still control all your displays with keyboard shortcuts and the panel remains accessible via the default toggle hotkey, which opens an app window instead.

---

## Tips

- Assign a quick Toggle Blackout hotkey to your most-used external display - great for instantly blocking a monitor when someone walks by.
- Use media keys for blackout if you have spare keys on your keyboard or a media controller.
- If a specific display is missing from the target picker (it shows as "Missing display"), it wasn't connected when the hotkey was created. The hotkey will resume working when the display reconnects.
