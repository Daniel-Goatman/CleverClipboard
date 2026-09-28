#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

usage() {
    print 'Usage: ./build.sh [--launch] [--force] [--replace-other-instances] [--development]'
    print '  --launch                  Restart this checkout app after building.'
    print '  --development             Include opt-in evaluation logging (never distribute this build).'
    print '  --force                   Recompile even when the signed app is current.'
    print '  --replace-other-instances Also stop CleverClipboard/legacy apps from other checkouts.'
}

launch=false
force=false
replace_other=false
development=false
swift_flags=()
for arg in "$@"; do
    case "$arg" in
        --launch) launch=true ;;
        --force) force=true ;;
        --development) development=true; swift_flags=(-D CLEVERCLIPBOARD_DEVELOPMENT) ;;
        --replace-other-instances) launch=true; replace_other=true ;;
        -h|--help) usage; exit 0 ;;
        *) print -u2 "Unknown option: $arg"; usage >&2; exit 2 ;;
    esac
done

app='CleverClipboard.app'
executable="$app/Contents/MacOS/CleverClipboard"
stamp='.build/cleverclipboard-build.sha256'
mkdir -p .build/module-cache results/jev-app

# Source/toolchain fingerprint avoids repeat compilation. The bundle must also
# pass signature and plist checks before it can be reused.
fingerprint=$(
    {
        print 'swift-version=5 optimization=-O target=arm64-apple-macos14.0'
        print -r -- "development=$development"
        xcrun --find swiftc
        xcrun swiftc --version 2>&1
        /usr/bin/shasum -a 256 build.sh Info.plist Sources/*.swift Resources/*
    } | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
)

current=false
if [[ "$force" == false && -f "$stamp" && -x "$executable" && -f "$app/Contents/Info.plist" ]]; then
    if [[ "$(/bin/cat "$stamp")" == "$fingerprint" ]] &&
       /usr/bin/cmp -s Info.plist "$app/Contents/Info.plist" &&
       /usr/bin/codesign --verify --deep --strict "$app" 2>/dev/null; then
        current=true
    fi
fi

if [[ "$current" == true ]]; then
    print 'Build is current; skipped compilation.'
else
    stage_root=$(/usr/bin/mktemp -d .build/cleverclipboard-stage.XXXXXXXX)
    stage_app="$stage_root/CleverClipboard.app"
    previous_app="$stage_root/previous.app"
    cleanup_stage() {
        if [[ -d "$previous_app" && ! -d "$app" ]]; then
            /bin/mv "$previous_app" "$app"
        fi
        /bin/rm -rf "$stage_root"
    }
    trap cleanup_stage EXIT
    /bin/mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources"
    xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
        -module-cache-path .build/module-cache "${swift_flags[@]}" Sources/*.swift \
        -o "$stage_app/Contents/MacOS/CleverClipboard"
    /bin/cp Info.plist "$stage_app/Contents/Info.plist"
    /bin/cp Resources/* "$stage_app/Contents/Resources/"

    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)
    /usr/bin/codesign --force --sign - --identifier "$bundle_id" "$stage_app"
    /usr/bin/codesign --verify --deep --strict "$stage_app"

    # The old bundle remains recoverable until the complete signed bundle is
    # installed. A failed final rename restores it via the exit trap.
    if [[ -d "$app" ]]; then
        /bin/mv "$app" "$previous_app"
    fi
    /bin/mv "$stage_app" "$app"
    print -r -- "$fingerprint" > "$stamp"
    cleanup_stage
    trap - EXIT
    print 'Built and locally signed CleverClipboard.app.'
fi

if [[ "$launch" == true ]]; then
    args=()
    if [[ "$replace_other" == true ]]; then args+=(--replace-other-instances); fi
    /usr/bin/python3 scripts/launch.py "${args[@]}"
fi
