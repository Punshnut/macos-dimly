The Texture Playground is a tiny corner of Dimly where you can write your own screen texture out of pure math - no photo, no scan, just numbers turning into a pattern you can actually use. You don't need to know anything about graphics programming to get something fun on screen in about a minute. Start from the template that's already there, change a number, watch it change live on your real monitor, and go from there.

This page is the friendly, no-experience-needed walkthrough. If you just want the quick facts, see the [Texture Playground section](Texture-Overlays#the-texture-playground) in the main Texture Overlays guide instead.

---

## Opening it

Go to **Settings → Textures** and click **New Texture Playground…**. A window opens with:

- A **code box** on the left - this is where you write (or just tweak) your texture.
- A **live preview** on the right, tiled 2×2 so you can see whether the pattern repeats cleanly ("seamlessly") with no visible seams.
- A **Preview Intensity** slider under the preview, defaulting to 50% - it doesn't just change the little preview, it also shows your texture live on every screen you have connected, at that strength, so you can judge it the way it'll actually look.
- An error strip that only appears if something's wrong with the code.

Nothing you do here is saved until you click **Save**. Closing the window (even with Cancel) puts every display back exactly the way it was.

## Why the preview never goes blank

Every time you stop typing for about half a second, Dimly tries to compile your code and update the preview. If what you typed doesn't compile - a typo, a missing bracket, mid-thought edits - the preview just keeps showing your **last successful result**, and the error strip explains what's wrong underneath. You can type freely without the window flashing blank at you.

## Your first edit

The template that's already loaded draws a simple paper-grain pattern. Try this:

1. Find the line that starts with `float grain = noise(uv * 32.0)...` and change `32.0` to `8.0`. Wait half a second - the grain gets coarser, both in the preview and on your real screen.
2. Find `float3 paper = float3(0.96, 0.95, 0.92) - grain * 0.08;` - those three numbers are the base color (red, green, blue, each 0 to 1). Try `float3(0.85, 0.90, 0.95)` for a cool blue-gray instead of warm paper.
3. Drag the **Preview Intensity** slider up and down and watch your real screen follow along live.

That's it - you've already made a variant. Everything past this point is optional, for when you want to go further.

## A gentle tour of what the code is doing

You don't need to become a shader programmer to have fun here, but a little context helps:

- **`uv`** is a position on the texture, from 0 to 1 across and down. Every point on the screen gets its own `uv`, and the same function runs for all of them.
- **`noise(...)`** is a helper already provided for you - it turns a position into a pseudo-random-looking value, which is what makes grain/paper/static-style patterns possible without an actual photo.
- **Multiplying `uv` by a number** (like the `32.0` above) controls how "zoomed in" the noise looks - bigger numbers mean finer, busier detail; smaller numbers mean bigger, smoother blobs.
- **"Tileable" / "seamless"** means the pattern lines up with itself at the edges, so it can repeat across your whole screen without visible seams. The template is built to already be seamless - that's why the 2×2 preview is there, so you can catch it if an edit accidentally breaks that.

If you want to go deeper, the template is standard [Metal Shading Language](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) - the same language and compiler Xcode itself uses - so any Metal shader reference applies here too. But plenty of people will never need to look past tweaking numbers, and that's a completely valid way to use this.

## Giving it depth (the 3D relief toggle)

Real paper and canvas aren't flat - light catches the grain and casts tiny shadows, which is a big part of what makes a texture feel calming instead of like a flat picture pasted on your screen. The Playground has a toggle for this:

- **On (default):** Dimly looks at how bright/dark your shader's output is at each point and automatically derives a simulated light-and-shadow relief from it - brighter areas read as "higher," darker as "lower." Most simple patterns look noticeably better with this on.
- **Off:** your shader's colors are used exactly as written, flat, with no automatic shading added - use this if you're deliberately painting in your own lighting/shadows in the code.

## Copy, Export, Save

- **Copy Code** puts the raw text on your clipboard - handy for pasting into a message, an issue, a gist, anywhere.
- **Export…** saves it as a plain `.metal` file you can keep, back up, or hand to someone else.
- **Save** compiles it one last time, renders it into your texture library, and it's immediately usable everywhere any other texture is - the per-display picker, the menu bar toggle, all of it. There's no separate "procedural" category to think about afterward; it just becomes a texture like any other.

## Share what you made

If you end up with a texture you like, share it - that's genuinely the fun part. Grab the code with **Copy Code** or **Export…** and:

- Paste it into a GitHub issue or a gist so others can try it.
- Open a pull request to get it considered as a **bundled default** everyone gets on first launch - drop the exported `.metal` file into `Resources/ExampleTextures/Procedural/` in a fork of the repo and send the PR. See [Contributing a texture](https://github.com/Punshnut/macos-dimly/blob/dev/CONTRIBUTING.md#contributing-a-texture) in `CONTRIBUTING.md` for the exact steps - it's a short one.

You don't need to be an expert to contribute something worth sharing. A few tweaked numbers on the template already counts.
