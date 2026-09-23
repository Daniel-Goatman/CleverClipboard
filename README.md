# Jev Clipboard

Local macOS menu-bar clipboard manager and Smart Paste selector. ⌘⇧V captures the focused destination, sends bounded text context and clipboard candidates to TypeSafe Jev 1.13, then pastes the selected existing item. It never generates replacement text. If Jev finds no suitable match, ordinary paste uses the current clipboard. Text is pasted as plain text so it adopts the destination's style; image and file formats remain intact.

## Build and run

Requires an Apple Silicon Mac running macOS 14+, Xcode command-line tools, and Apple's `/usr/bin/python3` (stdlib only). No package installation or local Laya model is needed.

```sh
./build.sh
open 'Jev Clipboard.app'
./test.sh
```

Keep the built `.app` in this project directory: it loads the adjacent `runtime/` folder. The app is currently a source-build prototype, without a signed or notarized downloadable release.

On first launch:

1. Copy your own TypeSafe API key, then choose **Troubleshooting → Set TypeSafe Key from Clipboard…** from the menu-bar icon. Hosted selections require internet access and may incur API charges.
2. Grant **Accessibility** so the app can read the focused input and send paste keystrokes. Grant **Screen Recording** for local OCR of visible context when Accessibility cannot supply enough information.
3. Copy some items or add saved entries, focus a destination in another app, and press **⌘⇧V**. Ordinary **⌘V** remains available.

The app uses the Keychain item `local.daniel.LayaClipboard.TypeSafe` / `api-key`. Key setup, permission prompts, Jev restart, and diagnostic timing are in the menu bar's **Troubleshooting** submenu. The bundle identifier remains `local.daniel.LayaClipboard` to preserve the integration. The unsigned app may need fresh Accessibility and Screen Recording grants after rebuilding or moving; verify its status from the running process rather than trusting System Settings switches alone.

## Clipboard data

The menu's **Open Clipboard…** window shows stored text or image thumbnails, source app, copy time, and the exact bounded item text Jev would receive at the current candidate count. Screenshots are stored as pasteable PNG, TIFF, JPEG, or HEIC; Vision OCR runs after copying and only bounded OCR text, not pixels, is sent to Jev. OCR may be pending briefly after a copy. **Always Available** supports up to 20 text, image or single-file entries. Use Add Entry to choose a type, enter a description, then Save Changes (⌘S). Image and file imports are independent local copies, so moving the original does not break an entry. Saved images accept PNG, JPEG, TIFF or HEIC. Existing text entries migrate automatically; their purpose hint becomes the description (or the old title if no hint was set).

Ordinary history is limited to 50 items and 128 MB total; text is capped at 256 KB and an image at 20 MB. Saved assets have a separate 50 MB per-file and 512 MB total limit. Older ordinary items are evicted as needed. Files are stored in `~/Library/Application Support/Jev Clipboard` with account-only permissions. They are **not app-level encrypted**. Pause Collection stops new capture; Clear History removes ordinary stored items and image files, but keeps saved entries and assets. Concealed and transient pasteboard types are ignored.

History from the previous memory-only app cannot be migrated. Clipboard contents, screen OCR, and model requests are not logged. The content-free diagnostic path `results/jev-app/launch-status.json` is for local verification and contains only readiness and permission flags.

## Selection and tests

Jev receives candidate text or bounded image OCR or file metadata, source app, kind, recency rank and age, plus each saved entry's description as its purpose hint. Image pixels and file bytes remain local. All valid saved entries are included in the 52-candidate request; newest ordinary history fills the remaining slots. For a focused plain text field or combo box, image and file candidates are filtered out before the request. Rich editors and windows without a focused text field keep every kind because the app or page may handle a paste itself. AX roles do not reveal every destination's accepted formats, so file pasting is not universal; an upload control may require its file picker. Jev chooses among the full eligible set using observed labels, text around the caret when available, visible editor context, candidate descriptions, and recency. A local tie-break prefers a matching description, then a recently copied item, only when candidates have similar Jev probabilities and the same pasteboard kind. If every candidate is implausible, the current clipboard is pasted.

`./test.sh` runs native context, history, storage, keyboard and fallback checks plus Jev request tests. `python3 Tests/benchmark_recency.py --baseline /path/to/historical/jev_selector.py` is an optional hosted synthetic benchmark requiring a compatible historical selector; it reads the existing Keychain key into memory, makes paid Jev requests and prints only fixture IDs and timings. It is not run by `test.sh`.

Destination context is hierarchical: `insertion` (exact adjoining text and replacement), `field` (label and instructions), `document` (earlier/later text and section), then `application`. The current line is separated from other lines without inferring a content type. When an AX insertion anchor exists, unrelated window titles and broad OCR are omitted. Missing anchors stay explicitly unavailable; visible OCR is never promoted into a fabricated caret line. This representation does not itself repair editors whose caret cannot be captured.

`python3 Tests/benchmark_hierarchy.py --rounds 2` compares the previous flat request against the hierarchy using synthetic fixtures, 44 candidates and alternating request order. It makes paid hosted requests using the existing key in memory. `--fixtures-only` generates the exact example request without network access. Results and the complete synthetic email request are in `results/hierarchy/`; API timings exclude native capture and paste.

## Privacy and limitations

Smart Paste sends bounded destination text and eligible clipboard candidate text/metadata to `api.typesafe.ai`. Depending on the destination, this can include text around the caret, app/window information, nearby labels, and OCR of visible content. This is **not fully offline**. Do not use Smart Paste with content you do not want sent to that service. Image pixels and attached file bytes are not uploaded by the selector.

Selection is probabilistic. Check important pastes; some apps do not expose a reliable insertion position or accept pasted files. There is no guaranteed latency or accuracy target. Ordinary history and saved assets persist locally and are excluded from this repository, as are API credentials, app bundles and diagnostic output.

Rich editors use Accessibility text-marker APIs when ordinary text/range attributes are unavailable. This is capability-based rather than specific to particular apps or content types. The local capture diagnostic reports capability flags and text lengths without recording draft text.

This repository contains source code and synthetic tests. No open-source license has been selected yet; public visibility alone does not grant a general license to reuse the code.
