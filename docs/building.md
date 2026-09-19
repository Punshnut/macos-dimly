# Building Dimly yourself

Dimly is open source, and you don't have to wait for a release or trust a download to use it - you can compile it straight from the source in this repository. This page walks through that, no development experience required.

A couple of things to know up front:

- A self-built copy is **not signed by the project maintainer**. It's an ad-hoc signed, unofficial "Community Build" - the app itself will tell you this on its Settings → About screen, with a link back here.
- Self-built copies **don't auto-update**. To get a newer version, pull the latest source and rebuild, or switch to an [official release](https://github.com/Punshnut/macos-dimly/releases/latest).
- This only builds an unsigned/ad-hoc app for running on your own Mac. It's not meant for redistributing to other people - share the source or point them at the official releases instead.

---

## 1. Install Xcode

You need the full Xcode app (free, from the App Store) - the Command Line Tools alone aren't enough, since Dimly's app icon is compiled with a tool that ships only with Xcode.

1. Open the **App Store** and search for **Xcode**.
2. Install it (it's a large download, so this can take a while).
3. Open Xcode once after installing so it can finish setting up its components.

Dimly targets **macOS 14 or later**, on Intel or Apple Silicon.

## 2. Get the source

If you're comfortable with git:

```bash
git clone https://github.com/Punshnut/macos-dimly.git
cd macos-dimly
```

If you're not, that's fine too:

1. Go to the [Dimly repository](https://github.com/Punshnut/macos-dimly) on GitHub.
2. Click the green **Code** button, then **Download ZIP**.
3. Unzip it, then open a **Terminal** window in that folder (right-click the folder in Finder → **New Terminal at Folder**, or drag the folder onto the Terminal icon after typing `cd `).

## 3. Run the build script

In Terminal, from inside the project folder:

```bash
./scripts/build_dimly.sh
```

This downloads Dimly's one dependency (Sparkle), compiles the app, builds the app icon, and produces a ready-to-run **Dimly.app** right in the project folder. It takes a few minutes the first time.

If you'd rather build for just your Mac's architecture (a bit faster), run `ARCHES="arm64" ./scripts/build_dimly.sh` on Apple Silicon, or `ARCHES="x86_64" ./scripts/build_dimly.sh` on Intel.

## 4. Install and launch it

1. Drag the new `Dimly.app` to your **Applications** folder (or just double-click it where it is).
2. On first launch, macOS will likely say it can't verify the developer - this is expected for a self-built app. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Dimly, then confirm once more.
3. Dimly should now appear in your menu bar like any other install.

If you downloaded a ZIP from GitHub rather than using git, macOS may be a little more insistent about this warning the first time, since the ZIP itself carries a quarantine flag - the same "Open Anyway" step clears it.

---

## Something not working?

- Build errors are almost always a missing or outdated Xcode - make sure it's fully installed and opened at least once.
- For anything about the app itself once it's running - DDC not detecting a monitor, display issues, and so on - see [Troubleshooting](troubleshooting.md), which is unrelated to how the app was built.
- Found an actual bug in the build script? [Open an issue](https://github.com/Punshnut/macos-dimly/issues/new) or, even better, see [CONTRIBUTING.md](../CONTRIBUTING.md) and send a PR.

That's it - happy building.
