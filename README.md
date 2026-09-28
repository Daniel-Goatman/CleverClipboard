<p align="center">
  <img src="docs/media/banner.svg" alt="CleverClipboard — macOS clipboard history and Smart Paste" width="100%">
</p>

<p align="center">
  A macOS clipboard manager with an experimental Smart Paste shortcut.<br>
  Personal hobby project. Written in Swift and SwiftUI.
</p>

<p align="center">
  <a href="#try-it">Try it</a> ·
  <a href="#smart-paste">Smart Paste</a> ·
  <a href="#data-and-privacy">Data and privacy</a> ·
  <a href="docs/GUIDE.md">Full guide</a>
</p>

---

## Clipboard history

CleverClipboard runs in the menu bar and stores recent text, links, images, and files. You can search your history, preview an item, and copy it again.

![CleverClipboard History: searchable clips on the left, with the selected link and its source on the right.](docs/media/history.png)

*The real app, filled with made-up demo data.*

| History | Always Available | Smart Paste |
| :--- | :--- | :--- |
| Search and preview recent copies. | Store saved text, images, and files with descriptions. | Press **⌘⇧V** to select an existing clip using destination context. |

## Saved entries

**Always Available** stores entries separately from recent history. It supports text, images, and files. Clearing history doesn't remove saved entries.

<details>
<summary><strong>Saved entries screenshot</strong></summary>

![CleverClipboard Always Available: saved descriptions and values, including a fictional support email, address, meeting link, and sign-off.](docs/media/always-available.png)

Give an entry a useful description, add its value, then choose **Save Changes** (⌘S).

</details>

## Smart Paste

Smart Paste sends destination context and eligible clipboard entries to TypeSafe Jev, which selects an existing item to paste.

1. **Copy a few things** as you normally would.
2. **Click where you want to paste**, then press **⌘⇧V**.
3. **TypeSafe Jev chooses an existing item** using destination context and eligible clips. It doesn't write new text.

Regular **⌘V** still works normally. If the model returns no match or confidence of 70% or less, Smart Paste falls back to the latest clipboard item. Network or invalid-response errors paste nothing.

Selection can be wrong, and some apps expose limited context. Check important pastes.

## Try it

You'll need **an Apple Silicon Mac, macOS 14+, and Xcode command-line tools** to build. Smart Paste also needs your own **TypeSafe API key** and an internet connection; API usage may cost money.

```sh
git clone https://github.com/Daniel-Goatman/CleverClipboard.git
cd CleverClipboard
./build.sh --launch
```

Then, from the menu-bar icon:

1. Open **TypeSafe API Key…** and choose **Verify & Save**. The key is stored in macOS Keychain.
2. Choose **Allow Accessibility…** and grant access in System Settings. Screen Recording is optional, for local OCR.
3. Copy a few items and try **⌘⇧V**, or choose **Open Clipboard…** to browse them yourself.

The build script makes a locally signed app. There isn't a notarized downloadable release yet. See the [setup and troubleshooting guide](docs/GUIDE.md#build-and-run) if permissions stop working after rebuilding.

## Data and privacy

**Smart Paste uses a hosted model.** It sends bounded clipboard text, destination text, and candidate metadata to `api.typesafe.ai`. Image pixels and file bytes stay local; extracted OCR text may be sent.

History and saved entries live on your Mac and aren't encrypted by the app. **Dataset recording is off by default.** You can optionally save Smart Paste attempts locally for evaluation or training. These records can contain clipboard excerpts and destination text; they aren't encrypted by the app or automatically uploaded. **Clear History does not delete dataset records.**

To enable recording for your macOS user account, run this and restart the app:

```sh
defaults write local.daniel.LayaClipboard SaveSmartPasteDataset -bool true
```

Use `-bool false` to disable it, then restart. This is a local preference; it isn't included when someone clones the repository. The preference domain retains an older internal identifier for compatibility.

Read the [storage and privacy details](docs/GUIDE.md#clipboard-data) and [dataset notes](DATASET.md) before trying it with private content.

## Development

The app uses native Swift networking and has no third-party runtime packages or local model. Python 3 is used for development tests and the launch helper.

```sh
./test.sh                 # Offline tests with synthetic data
./test.sh --interactive   # Also checks keyboard, pasteboard, and Vision on a desktop
```

| Topic | Documentation |
| :--- | :--- |
| Setup, limits, permissions, and selection behaviour | [Full guide](docs/GUIDE.md) |
| What the model sees | [Context contract](CONTEXT_CONTRACT.md) |
| Local attempt records | [Dataset notes](DATASET.md) |
| The icon and dark interface | [Design notes](docs/branding/README.md) |

---

No open-source license has been chosen yet.
