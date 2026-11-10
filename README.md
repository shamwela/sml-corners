# SML Corners

With SML Corners, you push a corner of your trackpad to start an action. You can set a different action for each of the four corners.

The default action for the top-right corner is a screenshot of an area. The app puts the screenshot on the clipboard.

You must have macOS 13 or later. The app operates on Apple silicon and Intel Macs.

## Install

### Download

1. Download the zip file from [Releases](https://github.com/shamwela/sml-corners/releases/latest).
2. Open the zip file.
3. Move **SML Corners** to the **Applications** folder.
4. Open **SML Corners**. macOS shows a warning. Click **Done**.
5. Go to **System Settings > Privacy & Security**.
6. Find the message *"SML Corners" was blocked*. Click **Open Anyway**.
7. Type your password. Click **Open Anyway** again.

NOTE: macOS shows the warning because the app does not have an Apple signature. Do steps 4 to 7 one time only.

### Homebrew

Type this command in Terminal:

```bash
brew install --cask shamwela/tap/sml-corners
```

## Give permission

The app must have Accessibility permission to find corner clicks.

1. Go to **System Settings > Privacy & Security > Accessibility**.
2. Set **SML Corners** to on.

## Use

1. Put one finger in a corner of the trackpad.
2. Push down until the trackpad clicks.
3. Lift your finger. The app starts the action.

To change the actions, click the menu bar icon. Then click **Settings…**.

## Uninstall

1. Click the menu bar icon. Then click **Quit SML Corners**.
2. Move **SML Corners** from **Applications** to the **Bin**.

## Developers

- To build and install, type `make install`.
- To make a release, change `VERSION` in the `Makefile`. Then type `make release`.
- The settings file is `~/.config/sml-corners/config.json`.

NOTE: The app uses a private macOS framework. A macOS update can stop the app.
