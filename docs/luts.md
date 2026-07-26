# LUT Library

A **LUT (Look-Up Table)** remaps the color output of a display using a calibration or creative curve. LUTs are applied at the gamma-table level - they affect the full display output, just like Appearance Filters. Manage your LUT library from **Settings → LUTs**, then assign LUTs to individual displays from **Settings → Displays → Image**.

---

## Supported formats

| Format | Description |
|---|---|
| `.cube` | Industry standard - used by DaVinci Resolve, Premiere Pro, Photoshop, Final Cut Pro. Supports both 1D and 3D LUTs. |
| `.3dl` | Autodesk / Flame format. 3D mesh LUT, 12-bit range. |
| `.lut` | 1D LUT format used by DaVinci Resolve and broadcast tools. |
| `.csv` | Comma- or tab-separated 1D table with R, G, B columns. |

---

## Bundled presets

Dimly ships with 5 ready-to-use presets - Cool Breeze, Soft Matte, Vivid, Film Curve, and Warm Amber. They're imported into your library automatically on first launch, so they're available in the LUT picker immediately without importing anything yourself.

---

## Importing a LUT

Click **Import LUT…** and choose a file. After import, the LUT appears in the library with a **color preview strip** and a badge showing its type and size (e.g. "3D · 33³" or "1D · 64").

---

## Assigning a LUT to a display

1. Go to **Settings → LUTs** and import a LUT file (or use one of the bundled presets).
2. In **Settings → Displays**, expand a display's **Image** section.
3. Choose a LUT from the **LUT** picker. Select **None** to remove it.

---

## 1D vs 3D LUTs

- **1D LUTs** remap each channel independently. These map exactly to the gamma table.
- **3D LUTs** apply full cross-channel color transforms. Dimly samples the neutral axis of 3D LUTs to derive per-channel curves - this works well for calibration LUTs but may not fully reproduce strong creative color grading effects.

---

## How LUTs apply

LUTs are reapplied automatically after sleep/wake and display reconnects. They compose with Appearance Filters - the filter is applied first, then the LUT curve.

---

## Renaming and deleting

Click **Rename** next to any LUT to give it a custom name. Click **Delete** (with confirmation) to remove a LUT from the library - any displays using it will revert to no LUT automatically.

---

## Backup and restore

LUT assignments are included in Settings Backup (Monitor Settings). When you export a backup and the LUT library toggle is included, the actual LUT file data is embedded in the backup - so restoring the backup on another Mac also restores the LUT files.
