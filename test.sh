#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build results
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/History.swift Tests/HistoryTests.swift -o .build/history-tests
.build/history-tests
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/Diagnostics.swift Sources/Context.swift Tests/ContextTests.swift -o .build/context-tests
.build/context-tests
python3 -m unittest discover -s Tests -p 'test_*.py' -v
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/PreviewPanel.swift Tests/PanelTests.swift -o .build/panel-tests
print 'For native rendering in an interactive macOS session: .build/panel-tests results/preview.png'

xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/Diagnostics.swift Tests/DiagnosticsTests.swift -o .build/diagnostics-tests
.build/diagnostics-tests

xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/PasteKeyboard.swift Tests/PasteKeyboardTests.swift -o .build/keyboard-tests
.build/keyboard-tests

xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/Diagnostics.swift Sources/Context.swift Sources/History.swift Sources/CandidateText.swift Sources/ModelWorker.swift Sources/JevCredential.swift Tests/FallbackTests.swift -o .build/fallback-tests
.build/fallback-tests

xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/History.swift Sources/ClipboardStore.swift Sources/CandidateText.swift Sources/ImageOCR.swift Tests/StorageTests.swift -o .build/storage-tests
.build/storage-tests

xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/History.swift Sources/ClipboardStore.swift Sources/ImageOCR.swift Sources/PasteboardPayload.swift Tests/AssetPasteboardTests.swift -o .build/asset-pasteboard-tests
.build/asset-pasteboard-tests

xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/History.swift Sources/ImageOCR.swift Sources/ImageThumbnail.swift Tests/ImageOCRTests.swift -o .build/image-tests
.build/image-tests
