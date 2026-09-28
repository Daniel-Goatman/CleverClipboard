#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
interactive=false
case "${1:-}" in
    '') ;;
    --interactive) interactive=true ;;
    *) print -u2 'Usage: ./test.sh [--interactive]'; exit 2 ;;
esac
mkdir -p .build/module-cache results
swift=(xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache)
core=(Sources/Diagnostics.swift Sources/Context.swift Sources/History.swift Sources/CandidateText.swift Sources/DestinationContext.swift Sources/JevRequest.swift)
client=("${core[@]}" Sources/JevCredential.swift Sources/JevClient.swift Sources/DevelopmentDataset.swift)
"${swift[@]}" -typecheck Sources/*.swift
"${swift[@]}" -D CLEVERCLIPBOARD_DEVELOPMENT -typecheck Sources/*.swift
"${swift[@]}" Sources/History.swift Tests/HistoryTests.swift -o .build/history-tests
.build/history-tests
"${swift[@]}" Sources/Diagnostics.swift Sources/Context.swift Tests/ContextTests.swift -o .build/context-tests
.build/context-tests
python3 -m unittest discover -s Tests -p 'test_*.py' -v
"${swift[@]}" Sources/Diagnostics.swift Sources/CarbonTheme.swift Sources/SmartPasteErrorWindow.swift Tests/SmartPasteErrorTests.swift -o .build/smart-paste-error-tests
.build/smart-paste-error-tests
"${swift[@]}" Sources/Diagnostics.swift Tests/DiagnosticsTests.swift -o .build/diagnostics-tests
.build/diagnostics-tests
"${swift[@]}" Sources/History.swift Sources/CandidateText.swift Tests/CandidateTextTests.swift -o .build/candidate-tests
.build/candidate-tests
"${swift[@]}" "${core[@]}" Tests/FallbackTests.swift -o .build/fallback-tests
.build/fallback-tests
"${swift[@]}" Sources/History.swift Sources/ClipboardStore.swift Sources/CandidateText.swift Sources/ImageOCR.swift Tests/StorageTests.swift -o .build/storage-tests
.build/storage-tests
"${swift[@]}" "${client[@]}" Tests/JevClientTests.swift -o .build/client-tests
.build/client-tests
"${swift[@]}" -D CLEVERCLIPBOARD_DEVELOPMENT "${client[@]}" Tests/JevClientTests.swift -o .build/development-client-tests
.build/development-client-tests
"${swift[@]}" "${client[@]}" Sources/CarbonTheme.swift Sources/TypeSafeKeyWindow.swift Tests/TypeSafeKeyTests.swift -o .build/key-tests
.build/key-tests
"${swift[@]}" Sources/History.swift Sources/CandidateText.swift Sources/AppBrand.swift Sources/CarbonTheme.swift Sources/ItemPreview.swift Sources/ImageThumbnail.swift Sources/HistoryWindow.swift Tests/CarbonTests.swift -o .build/carbon-tests
.build/carbon-tests
"${swift[@]}" Sources/History.swift Sources/ClipboardStore.swift Sources/ImageOCR.swift Sources/PasteboardPayload.swift Tests/CarbonFileTests.swift -o .build/carbon-file-tests
.build/carbon-file-tests
python3 scripts/check_native_request.py
python3 scripts/check_combined_context.py
if [[ "$interactive" == true ]]; then
    "${swift[@]}" Sources/AppBrand.swift Sources/CarbonTheme.swift Sources/SettingsWindow.swift Tests/PermissionPresentationTests.swift -o .build/permission-presentation-tests
    .build/permission-presentation-tests output/permission-fix
    .build/smart-paste-error-tests --render output/permission-fix/errors
    "${swift[@]}" Sources/PasteKeyboard.swift Tests/PasteKeyboardTests.swift -o .build/keyboard-tests
    .build/keyboard-tests
    "${swift[@]}" Sources/History.swift Sources/ClipboardStore.swift Sources/ImageOCR.swift Sources/PasteboardPayload.swift Tests/AssetPasteboardTests.swift -o .build/asset-pasteboard-tests
    .build/asset-pasteboard-tests
    "${swift[@]}" Sources/History.swift Sources/ImageOCR.swift Sources/ImageThumbnail.swift Tests/ImageOCRTests.swift -o .build/image-tests
    .build/image-tests
else
    print 'Interactive keyboard/pasteboard/Vision rendering checks not run. Use ./test.sh --interactive in a desktop session.'
fi
