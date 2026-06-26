#!/bin/bash
# build.sh — Xcode command-line build for unlock_academia.dylib
# Requires: macOS + Xcode 14+ (with iOS SDK)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh                    # arm64 release
#   ./build.sh -s "path/to/ipa"   # build + inject into IPA
#   ./build.sh --universal        # arm64 + arm64e universal

set -euo pipefail

SDK="${SDK:-iphoneos}"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path 2>/dev/null || echo '')"
if [ -z "$SYSROOT" ]; then
    echo "ERROR: iOS SDK not found. Ensure Xcode is installed: xcode-select --install"
    exit 1
fi

OUT="${OUT:-unlock_academia.dylib}"
ARCH="${ARCH:-arm64}"
MIN_OS="${MIN_OS:-14.0}"

echo "[+] Building $OUT ($ARCH) with SDK $SDK..."

xcrun -sdk "$SDK" clang \
    -arch "$ARCH" \
    -mios-version-min="$MIN_OS" \
    -isysroot "$SYSROOT" \
    -fobjc-arc \
    -fobjc-weak \
    -O2 \
    -Wall \
    -Wextra \
    -Wno-unused-parameter \
    -Wno-deprecated-declarations \
    -dynamiclib \
    -install_name "/Library/MobileSubstrate/DynamicLibraries/unlock_academia.dylib" \
    -o "$OUT" \
    unlock_academia.m BypassSettings.m SwizzleHelper.m BypassHooks.m UnlockAcademiaMenuView.m \
    -framework Foundation \
    -framework UIKit \
    -framework CoreGraphics

echo "[+] Signing $OUT with ad-hoc identity..."
codesign -f -s - "$OUT"

echo "[+] Done! $OUT ($(file "$OUT" | sed 's/.*://'))"
ls -lh "$OUT"

# --- Optional: inject into an IPA ---
if [ "${1:-}" == "-s" ] && [ -n "${2:-}" ]; then
    IPA="$2"
    echo "[+] Injecting $OUT into $IPA..."
    
    TMPDIR=$(mktemp -d)
    unzip -q "$IPA" -d "$TMPDIR"
    
    # Copy dylib into Frameworks
    cp "$OUT" "$TMPDIR/Payload/"*.app/Frameworks/ 2>/dev/null || \
        cp "$OUT" "$TMPDIR/Payload/"*.app/
    
    # Add load command via optool
    if command -v optool &>/dev/null; then
        APP_BIN=$(find "$TMPDIR/Payload" -name "*.app" -type d | head -1)/$(basename "$TMPDIR/Payload"/*.app .app)
        if [ -f "$APP_BIN" ]; then
            optool install -c load -p "@executable_path/Frameworks/$OUT" -t "$APP_BIN"
        fi
    else
        echo "[!] optool not found. Add LC_LOAD_DYLIB manually with insert_dylib:"
        echo "    insert_dylib @executable_path/Frameworks/$OUT \"$APP_BIN\""
    fi
    
    # Repack
    pushd "$TMPDIR" >/dev/null
    mv "Payload/"*.app/Info.plist Info.plist 2>/dev/null || true
    zip -qr "${IPA%.ipa}-injected.ipa" Payload/
    popd >/dev/null
    rm -rf "$TMPDIR"
    
    echo "[+] Injected IPA: ${IPA%.ipa}-injected.ipa"
fi
