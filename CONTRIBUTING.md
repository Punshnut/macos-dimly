# Contributing to Dimly

Thanks for wanting to dig into Dimly. This page covers building it for development, the shape of the codebase, and how to send a pull request. If you just want to run a compiled copy without touching code, see [docs/building.md](docs/building.md) instead - it's the friendlier, no-experience-needed version of the same build.

## Quick start

```bash
git clone https://github.com/Punshnut/macos-dimly.git
cd macos-dimly
open Package.swift          # opens the project in Xcode
```

From there you have two ways to build:

- **`swift run dimly`** - fastest way to iterate on logic. Builds and runs the executable directly, but skips app-bundle assembly (no compiled icon, no embedded Sparkle framework, no Info.plist). Fine for most SwiftUI/logic changes; less useful if you're touching anything that depends on running as a real `.app` (menu bar behavior, Sparkle, launch-at-login, DDC/AVService calls that expect a bundle identity).
- **`./scripts/build_dimly.sh`** - produces a full, ad-hoc signed `Dimly.app` just like an end user would build, icon and all. Use this when you want to actually run and click around a real build. See [scripts/README.md](scripts/README.md) for what it does.

Requirements: **macOS 14+**, **Xcode** with the Swift 6.2 toolchain (the version in `Package.swift`'s `swift-tools-version` line). A real external monitor helps if you're touching DDC/CI code, but plenty of the app - overlay mode, profiles, scheduling, UI - works fine without one.

## Project layout

- `App/` - all Swift source. SwiftUI for the UI, AppKit where SwiftUI doesn't reach (menu bar item, display/window management), plus the DDC/CI and CoreDisplay integration.
- `Resources/` - `Info.plist`, the app icon (`Dimly.icon`, an Icon Composer bundle), bundled example LUTs and textures, and one `.lproj` folder per supported localization.
- `docs/` - the user guide (linked from the README).
- `scripts/` - the public build scripts covered above.
- `Media/` - screenshots and the logo used in the README.

## What's out of scope for a PR

Code signing, notarization, and Sparkle's update-signing key are deliberately kept out of this repository and off of GitHub - they're maintainer-only and handled with private tooling. You'll never need to touch any of that to build, test, or contribute a change; `scripts/build_dimly.sh` covers everything a PR needs.

## Making changes

- Match the existing style in the file you're editing rather than introducing a new pattern - this codebase leans on SwiftUI views composed from small helpers (see `SettingsRootView.swift` for the general shape of a settings page).
- Don't add a new dependency without opening an issue first to discuss it; Sparkle is currently the only external package for a reason.
- If you're changing anything DDC-related, please test against real hardware if you can, and mention what you tested with (Mac architecture, cable type, monitor make/model) in your PR description - DDC behavior varies a lot between setups, and the [DDC/CI compatibility notes](README.md#ddcci-and-external-monitors) and [Troubleshooting guide](docs/troubleshooting.md) exist because of exactly that variance.
- Adding a new user-facing string? It should go through the localization system like the rest of the UI (`String(localized:)` plus an entry in `Resources/en.lproj/Localizable.strings`) rather than a hardcoded literal, so translators can pick it up - translations into other languages aren't required from you, just the English source string.

## Contributing a texture

Bundled example textures (Settings → Textures) work the same way as bundled LUT presets: drop files into `Resources/ExampleTextures/` and Dimly seeds them into new users' libraries on first launch.

- A regular image texture: add the diffuse image (`.png`/`.jpg`/`.jpeg`/`.heic`/`.tiff`), plus an optional normal/height map named `<same base name>_normal.<ext>` if you have one - Dimly pairs them automatically.
- A procedural texture written in the [Texture Playground](docs/textures.md#the-texture-playground): export it from the Playground (**Export…**) and drop the resulting `.metal` file into `Resources/ExampleTextures/Procedural/`.

Either way, keep it tileable/seamless - that's the whole point of an overlay texture - and open a PR the same way as any other change.

## Submitting a pull request

1. Fork the repo and create a branch for your change.
2. Keep PRs focused - one feature or fix per PR is easier to review than several bundled together.
3. Describe what you tested and how, especially for display/DDC-related changes.
4. Open the PR against the `dev` branch.

If you're fixing something small (typo, obvious bug) feel free to just send the PR. For anything larger - a new feature, a behavior change - opening an issue first to talk it through saves everyone time.

Thanks again for contributing.
