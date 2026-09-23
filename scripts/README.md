# Build scripts

These are the public, signing-free scripts for compiling Dimly yourself. If you're looking for the full walkthrough (installing Xcode, running these, dealing with Gatekeeper), see the [Building wiki page](https://github.com/Punshnut/macos-dimly/wiki/Building) instead - this page is just a quick index.

| Script | What it does |
|---|---|
| `build_dimly.sh` | Compiles Dimly with Swift Package Manager, assembles `Dimly.app`, and ad-hoc signs it so it runs locally. This is the one you want. |
| `build_dmg.sh` | Optional - packages an already-built `Dimly.app` into a drag-to-install `.dmg`. Not required to just run the app. |

## What's different from official releases

A copy built with these scripts:

- Is **ad-hoc signed**, not signed with the maintainer's Developer ID certificate. macOS will still ask you to confirm "Open Anyway" the first time you launch it.
- Is stamped as a **Community Build** in its Info.plist and in the app's own Settings → About screen, with a link back to the official project.
- Has **Sparkle auto-updates disabled**. Re-run `build_dimly.sh` after pulling the latest source to update, or grab an [official release](https://github.com/Punshnut/macos-dimly/releases) instead.

There's nothing here related to code signing certificates, notarization, or Sparkle's private update-signing key - those stay private and are only used for official releases.
