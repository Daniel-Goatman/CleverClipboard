# Cuekit

Local macOS menu-bar clipboard manager and Smart Paste selector. ⌘⇧V captures the focused destination, sends bounded text context and clipboard candidates to TypeSafe Jev 1.13, then pastes the selected existing item. It never generates replacement text. If Jev returns no suitable match or confidence at or below 70%, Smart Paste uses the latest clipboard item instead. Network or invalid-response errors paste nothing. Text is pasted as plain text so it adopts the destination's style; image and file formats remain intact.

## First-time setup

1. Put **Cuekit.app** in Applications and open it. It lives in the menu bar.
2. Choose **TypeSafe API Key…** in Cuekit’s menu, enter your key in the masked field, then click **Verify & Save**. Cuekit checks it with TypeSafe and saves it in macOS Keychain only after successful verification. Invalid keys show an inline error; failed verification leaves your existing key unchanged. Collection pauses while this window is open, and an exact saved-key copy is removed from history without clearing unrelated entries.
3. Choose **Allow Accessibility…** and grant Cuekit access in System Settings. This is required for Smart Paste. Screen Recording is optional; it supplies local OCR when accessible context is insufficient.
4. Copy a few items, click a destination in another app, then press **⌘⇧V**. Jev chooses an existing item; **⌘V** still pastes normally. Use **Open Clipboard…** to inspect history and **Always Available** for saved entries.

You need your own TypeSafe account/key and internet connection. Hosted selections may incur API charges. The installed app needs no Python, package manager, or local model. This repository currently produces a locally signed prototype, not a notarized downloadable release; build it below if you do not already have an app bundle.

## Interface

Cuekit uses an always-dark appearance: charcoal grain, warm ivory text, native system typography, and the stepped-stack dock icon. **Settings…** (⌘,) opens General, Smart Paste, and Connection. Existing menu actions remain available.

History supports local search (⌘F), a selected-item detail view, and Copy/Delete actions. Standalone HTTP(S) URLs get a local domain card; prose, including email drafts, stays plain text. Images show compact thumbnails; PDFs use a monochrome document glyph. Click either to inspect the original image or PDF locally. No URL metadata is fetched. Always Available retains Description/Value fields, Text/Image/File imports, Replace, and explicit Save Changes (⌘S). Unsaved edits survive status refreshes; closing or quitting prompts to save or discard them.

Copied regular files are captured into History as independent local snapshots, at most 20 MB each and within the existing 50-item/128 MB limits. Folders, symbolic links, empty, unreadable, and oversized files are skipped. A new clipboard change, clearing History, or opening key entry cancels a pending capture. File bytes stay local; Smart Paste receives file metadata. Clearing/evicting ordinary history cleans its snapshots independently from Always Available; the file currently copied by Cuekit stays available until its clipboard protection is released and a subsequent save prunes it.

## Build and run

Requires an Apple Silicon Mac running macOS 14+ and Xcode command-line tools. Python 3 (stdlib only) is used for development tests and the optional launch-verification script; production requests use Swift URLSession. No third-party packages are required.

From the checkout you want to run, use one command:

```sh
./build.sh --launch
```

The script builds from the current checkout (switch to `main` first when you want the main build). It hashes the Swift sources, icon resources, `Info.plist`, build script, and Swift compiler to skip compilation when the signed bundle is current. The approved stepped-stack icon is included in the bundle, menu bar, and clipboard window. A changed build is compiled in a staging directory, locally ad hoc signed, verified, and installed as a complete bundle. `--launch` then restarts only this checkout's process and verifies a fresh launch report. It refuses to start while a Jev app from another checkout is running, because that app may own ⌘⇧V. The reported path tells you which instance to quit.

```sh
./build.sh                            # Build and sign only; running app stays on its old build
./build.sh --force --launch           # Recompile and restart even if inputs are unchanged
./build.sh --replace-other-instances  # Also quit other Jev instances, then launch this one
./test.sh                             # Offline synthetic suite; no real clipboard or hosted calls
./test.sh --interactive               # Also exercise keyboard, pasteboard and Vision on a desktop
./build.sh --development              # Explicit development logging build; do not distribute
```

Use `--replace-other-instances` only when you intend to stop every other running Cuekit build; it matches their exact executable paths before sending a graceful terminate signal. The launcher never force kills a stuck process. It exits with code 2 if the app launched but the TypeSafe connection, shortcut, or Accessibility permission is not ready, and prints the reason. Screen Recording is optional and is reported separately. In a sandboxed automation shell, macOS may block process inspection or Launch Services; run the command in a normal Terminal session if that happens.

The built `.app` contains the native executable and resources, with no Python worker or runtime folder. It can be installed as `/Applications/Cuekit.app` and opened normally. To verify an installed copy from this source checkout, use `python3 scripts/launch.py --app /Applications/Cuekit.app`; add `--replace-other-instances` only when intentionally replacing another running build.

The app uses the Keychain item `local.daniel.LayaClipboard.TypeSafe` / `api-key`. Key setup, permissions and reconnection are available directly in the menu, with symbols beside each action. Hover over the connection status for details. The bundle identifier remains `local.daniel.LayaClipboard` to preserve the integration. Rebuilding or moving the locally signed app may require fresh Accessibility and Screen Recording grants. If `--launch` reports Accessibility off, choose **Allow Accessibility…**, grant the running app access in System Settings, then retry `./build.sh --launch`. If a permission switch is already on but the new process still reports it off, remove the stale entry and add the exact `Cuekit.app` from this checkout in **Privacy & Security → Accessibility**. Smart Paste requires Accessibility; Screen Recording supplies optional visible-context OCR. Verify permission status from the new process rather than trusting an old System Settings switch.

At startup, an authenticated `GET /v1/models` verifies the TypeSafe connection before Smart Paste reports ready. This sends the API key but no clipboard/destination content and does not run the selection model. If connection verification fails, the app retries every 45 seconds while unavailable. Use **Reconnect TypeSafe** to retry immediately after changing credentials or restoring connectivity.

## Clipboard data

The menu's **Open Clipboard…** window shows stored text or image thumbnails, source app, copy time, and an illustrative **Selection excerpt**. The final request may shorten it further depending on the destination and other candidates; source metadata and saved-entry descriptions are also sent. Screenshots are stored as pasteable PNG, TIFF, JPEG, or HEIC; Vision OCR runs after copying and only bounded OCR text, not pixels, is sent to Jev. OCR may be pending briefly after a copy. **Always Available** supports up to 20 text, image or single-file entries. Use Add Entry to choose a type, enter a description, then Save Changes (⌘S). Image and file imports are independent local copies, so moving the original does not break an entry. Saved images accept PNG, JPEG, TIFF or HEIC. Existing text entries migrate automatically; their purpose hint becomes the description (or the old title if no hint was set).

Ordinary history is limited to 50 items and 128 MB total; text is capped at 256 KB and an image or file snapshot at 20 MB. Saved assets have a separate 50 MB per-file and 512 MB total limit. Older ordinary items are evicted as needed. Files continue to be stored in `~/Library/Application Support/Jev Clipboard` with account-only permissions so existing history and saved entries survive the Cuekit rename. They are **not app-level encrypted**. Clear History removes ordinary stored items and image files, but keeps saved entries and assets. Concealed and transient pasteboard types are ignored.

If the library cannot be read (including an unsupported version), Cuekit preserves existing files and disables saving instead of overwriting the library or deleting assets. Restore `Library.json` from a backup and restart. History from the previous memory-only app cannot be migrated.

Normal builds do not collect evaluation datasets or emit evaluation timing logs. Development builds can opt into local request/response recording; see [DATASET.md](DATASET.md). Existing development records are retained until separately removed; Clear History does not delete them. Content-free launch diagnostics remain at `results/jev-app/launch-status.json` in a source checkout, or under the app’s Application Support directory for an installed copy. They report readiness and permissions, not clipboard text.

## Selection and tests

Jev receives candidate text or bounded image OCR or file metadata, source app, kind, recency rank and age, plus each saved entry's description as its purpose hint. Image pixels and file bytes remain local. All valid saved entries are included in the 52-candidate request; newest ordinary history fills the remaining slots. For a focused plain text field or combo box, image and file candidates are filtered out before the request. Rich editors and windows without a focused text field keep every kind because the app or page may handle a paste itself. AX roles do not reveal every destination's accepted formats, so file pasting is not universal; an upload control may require its file picker. Jev chooses among the full eligible set using observed labels, text around the caret when available, visible editor context, candidate descriptions, and recency. Jev alone chooses the item: local hint/recency rules do not override its choice. Jev’s chosen item is used only when its confidence is **strictly above 70%**. Confidence at or below 70%, or a valid `NONE` response, uses the latest clipboard item. This confidence threshold is a selection policy, not a measured accuracy guarantee. Errors paste nothing. Focus and clipboard-change checks still prevent a delayed response from pasting into a changed destination.

`./test.sh` runs offline native context, history, storage, fallback, mocked networking and request-parity tests, plus the Python development reference tests. Keyboard, pasteboard and Vision rendering checks require `--interactive` in a desktop session. `python3 Tests/benchmark_recency.py --baseline /path/to/historical/jev_selector.py` is an optional hosted synthetic benchmark requiring a compatible historical selector; it reads the existing Keychain key into memory, makes paid Jev requests and prints only fixture IDs and timings. It is not run by `test.sh`.

Destination context is hierarchical: `insertion` (exact adjoining text and replacement), `field` (label and instructions), `document` (earlier/later text and section), then `application`. The current line is separated from other lines without inferring a content type. When an AX insertion anchor exists, it takes priority; application/window metadata remains lower-priority evidence and broad OCR is not treated as caret text. Missing anchors stay explicitly unavailable; visible OCR is never promoted into a fabricated caret line. This representation does not itself repair editors whose caret cannot be captured.

`python3 Tests/benchmark_hierarchy.py --rounds 2` compares the previous flat request against the hierarchy using synthetic fixtures, 44 candidates and alternating request order. It makes paid hosted requests using the existing key in memory. `--fixtures-only` generates the exact example request without network access. Results and the complete synthetic email request are in `results/hierarchy/`; API timings exclude native capture and paste.

## Privacy and limitations

Smart Paste sends bounded destination text and eligible clipboard candidate text/metadata to `api.typesafe.ai`. Depending on the destination, this can include text around the caret, app/window information, nearby labels, and OCR of visible content. This is **not fully offline**. Do not use Smart Paste with content you do not want sent to that service. Image pixels and attached file bytes are not uploaded by the selector.

Selection is probabilistic. Check important pastes; some apps do not expose a reliable insertion position or accept pasted files. There is no guaranteed latency or accuracy target. Ordinary history and saved assets persist locally and are excluded from this repository, as are API credentials, app bundles and diagnostic output.

Rich editors use Accessibility text-marker APIs when ordinary text/range attributes are unavailable. This is capability-based rather than specific to particular apps or content types. The local capture diagnostic reports capability flags and text lengths without recording draft text.

This repository contains source code and synthetic tests. No open-source license has been selected yet; public visibility alone does not grant a general license to reuse the code.
