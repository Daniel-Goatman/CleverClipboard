# Cuekit branding

The approved mark is **2 — Stepped stack**, with the selected middle text card offset to the right in front of two grey cards. `approved-stepped-stack.png` records Daniel's selected concept.

`Resources/Cuekit.png` is the standalone transparent app-icon master prepared from that concept with the built-in image generator. The edit preserved the stepped stack, charcoal/grey line art, and ivory rounded-square tile while removing the presentation background, duplicate preview, and label. `Resources/Cuekit.icns` contains the standard 16–512 point and Retina representations packaged with Apple's `sips` and `iconutil`.

`Sources/AppBrand.swift` supplies the app name, packaged icon, and a native template adaptation of the same mark for the menu bar. The small glyph uses one text stroke per card and transparency between outlines so macOS can render it correctly in either appearance.

The bundle identifier, executable name, Keychain service, clipboard storage directory, and backend diagnostic paths retain their existing identities. They are compatibility details, not product branding.

To regenerate the `.icns`, resize the master to the standard files in a `Cuekit.iconset` folder (16, 32, 128, 256, 512 pixels and each corresponding `@2x` file), then run `iconutil -c icns Cuekit.iconset -o Resources/Cuekit.icns`.


## Dark interface (2026-09-26)

The selected direction uses always-dark graphite, stationary paper-like grain, ivory foreground, and neutral macOS system typography. The stepped-stack geometry remains the brand identity. The current PNG and ICNS are deterministic native renditions built by `scripts/render_carbon_icon.swift`, with small-size optical adjustments. The older generated ivory master is preserved in the local task baseline; it is no longer the current icon.

`Sources/CarbonTheme.swift` owns shared surface, grain, control and text tokens. Native menus retain macOS semantics in the app's dark appearance. Settings, history, saved entries, secure key entry and the nonactivating preview panel share this appearance. Compact images show their actual thumbnails; PDFs use a document glyph, with full-content previews available on demand.

Regenerate the master/iconset by compiling `scripts/render_carbon_icon.swift` with Swift, running it with an output directory, then packaging its `Cuekit.iconset` with `iconutil`. This does not sign or install the app. Copy the resulting PNG/ICNS into Resources before building.

Refinements: History / Always Available use grey segmented controls with a subtle gradient. Secondary actions are borderless and regular-weight; only the primary save action is filled. Read-only filenames and link/image/PDF widgets sit directly on the background. Editable fields retain subtle outlines. Plain-text entries have no redundant type badge. Both pages stay mounted to preserve editing/scroll state and avoid reconstructing the native list on tab switches.

General uses continuous flat rows and soft separators, without bordered information cards or an appearance explainer. Settings contains General, Smart Paste and Connection; the Privacy page has been removed. Permission actions remain in Smart Paste.

Settings uses the packaged dock artwork and has no internal appearance name in its sidebar. Permission rows show Granted or Not granted independently of Required or Optional. Status refreshes when the app becomes active.
