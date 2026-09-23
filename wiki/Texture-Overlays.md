*Available since Dimly 2026.7.*

A **texture overlay** lays a subtle material - paper, canvas, linen, or anything you import or write yourself - over a display, with real 3D relief shading from a normal/height map. It's meant to make long reading or writing sessions easier on the eyes than a flat, glowing panel. Manage your texture library from **Settings → Textures**, then assign textures to individual displays from **Settings → Displays → Image**.

---

## Supported formats

| Format | Description |
|---|---|
| `.png`, `.jpg` / `.jpeg`, `.heic`, `.tiff` | Any raster material texture - ideally seamless/tileable. |
| `.svg` | Rasterized on import at a resolution suited to your display's backing scale. |
| Diffuse + normal/height pairs | Drop in two files that share a base name with a `_normal` or `_height` suffix (the convention used by most PBR material packs) and Dimly pairs them automatically into one texture with real relief shading. |

If a texture has no explicit normal/height map, Dimly can derive one from its luminance automatically ("auto-generate relief") - toggle this per texture in the library.

---

## Bundled textures

Dimly ships with three ready-to-use paper/canvas/linen textures, each with its own normal map for relief shading. They're imported into your library automatically on first launch.

---

## Importing a texture

Click **Import Texture…** and choose a file (or a diffuse + normal/height pair, imported one at a time - Dimly links them by filename). Textures appear in the library as thumbnails; procedural ones (see below) show a small code badge.

---

## Assigning a texture to a display

1. Go to **Settings → Textures** and import a texture (or use a bundled one).
2. In **Settings → Displays**, expand a display's **Image** section.
3. Choose a texture from the **Texture** picker. Select **None** to remove it.
4. Adjust **Opacity**, **Blend Mode** (Normal, Multiply, Overlay, Soft Light, Screen), and **Tile Scale** to taste - these appear once a texture is assigned.

Texture overlays are per-display, independent of blackout or brightness, and are saved with **Profiles**.

---

## Switching from the menu bar

**Per display:** every display tile/row in the menu bar panel has a small round texture button, right next to the sleep/wake and brightness controls. Click it to cycle that one display through your **Cycle Favorites** (see below), including an **off** step at the end of the rotation. Right-click (or Control-click) it instead to open a short list showing every favorite with a thumbnail and name, plus **Off** - pick any one directly rather than clicking through the rotation. The button itself always shows the display's current texture as a live thumbnail, so you can see what's active without opening anything.

**All displays at once:** a "Texture" quick-action button in the Quick Actions section steps every display through the same favorites rotation in lockstep - it also has an **off** step at the end. Build the **Cycle Favorites** list in Settings → Textures - drag to reorder, or remove entries you don't want in the rotation.

Prefer per-display control from a menu instead of a button? Switch to **Grid** mode in Settings → Textures: it replaces the Quick Actions cycle button with a popover showing a thumbnail picker for every display at once.

The Panic hotkey/button (`Ctrl` + `Option` + `Shift` + `P`, or the Quick Actions panic button) also turns every display's texture off, alongside its usual blackout/brightness restore - it's a full "back to a plain screen" reset.

---

## The Texture Playground

Want a texture that's pure math instead of a photo? Click **New Texture Playground…** in Settings → Textures. It's a small, plain-text code box - no project files, no autocomplete - where you write a texture as a [Metal Shading Language](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) fragment function, with a live preview on your actual screens and an intensity slider so you can judge it at real-world strength. **Never written a shader before? Start with the full walkthrough: [The Texture Playground, step by step](Texture-Playground).**

The short version:
- **Live preview, everywhere** - your code recompiles about 400ms after you stop typing, and the result shows immediately on every connected display (not just the small in-sheet swatch), at whatever intensity the **Preview Intensity** slider is set to (50% by default). A failing compile keeps showing your last good result and prints the compiler's error below the editor, so nothing ever goes blank mid-edit. Every display reverts to its own real texture/opacity/settings the moment you close the Playground.
- **3D relief toggle** - either bake your own lighting into the shader's color output, or output a height/luminance field and let Dimly's usual auto-relief shading take it from there.
- **Copy Code** / **Export…** - grab the raw `.metal` source to paste into an issue, a gist, a PR, wherever - or save it as a plain file. Nothing proprietary; it's just text.
- **Save** compiles once, renders a 512×512 tileable bitmap, and adds it to your library like any imported texture - no separate "procedural" section to think about afterward.

Made something good? The full guide ends with how to [share it](Texture-Playground#share-what-you-made) - including how to get it considered as a bundled default for every Dimly user.

---

## Backup and restore

Texture assignments (including opacity, blend mode, and tile scale) are captured by **Profiles**, just like LUT assignments. Texture library files themselves live under `~/Library/Application Support/Dimly/Textures/` on disk.
