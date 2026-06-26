# unlock_academia.dylib

Runtime bypass dylib for Academia iOS v1.9.14 (build 149).

**Purpose:** Educational security research — bypasses jailbreak detection, screenshot/recording prevention, and revenue protection to evaluate defensive fail-closed gate.

## What It Bypasses

| # | Target | Mechanism |
|---|--------|-----------|
| 1 | safe_device jailbreak checks | Hooks `SafeDeviceJailbreakDetection` (all class methods) + `SafeDevicePlugin` (Flutter channel) |
| 2 | DTTJailbreakDetection | Hooks class methods `isJailbroken`/`isPirated` |
| 3 | ScreenPreventerKit | Swizzles `ScreenPreventer`/`ScreenshotPreventer` properties (`enabled`, `enabledPreventScreenshot`, etc.) |
| 4 | UIKit screenshot | Hooks `UIScreen.isCaptured`, `UITextField.isSecureTextEntry`, removes screenshot/recording notifications |
| 5 | RevenueCat (if present) | Forced `isActive=YES`, `expirationDate=nil` on `RCEntitlementInfo` |
| 6 | Flutter method channel | Intercepts `SafeDevicePlugin.handleMethodCall:result:` — always returns unlocked |

## Build Methods

### A. Theos (macOS or jailbroken iOS)

```bash
# Install Theos: https://theos.dev/docs/installation
export THEOS=~/theos
make clean
make package
# Output: .theos/obj/debug/arm64/unlock_academia.dylib
```

### B. Xcode command-line (macOS only)

```bash
chmod +x build.sh
./build.sh                  # → unlock_academia.dylib (arm64)
./build.sh -s path/to.ipa   # build + inject into IPA
```

### C. Manual clang (advanced)

```bash
xcrun -sdk iphoneos clang \
  -arch arm64 \
  -mios-version-min=14.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -fobjc-arc -O2 \
  -dynamiclib \
  -o unlock_academia.dylib \
  unlock_academia.m \
  -framework Foundation -framework UIKit
```

## Injection / Sideload (Mode A)

1. Decrypt IPA (if App Store app)
2. `cp unlock_academia.dylib Payload/Runner.app/Frameworks/`
3. Add LC_LOAD_DYLIB to main Mach-O:
   - `optool install -c load -p @executable_path/Frameworks/unlock_academia.dylib -t "Payload/Runner.app/Runner"`
   - Or: `insert_dylib @executable_path/Frameworks/unlock_academia.dylib Payload/Runner.app/Runner --inplace`
4. Re-sign: `codesign -f -s "Apple Distribution: ..." --deep Payload/Runner.app`
5. Repack as IPA and sideload via AltStore, SideStore, or TrollStore (if applicable)

## Verification

After sideloading, check console logs for:

```
[unlock_academia] dylib loaded. Applying runtime bypasses...
[unlock_academia] SafeDeviceJailbreakDetection hooked
[unlock_academia] SafeDevicePlugin: instance methods hooked
[unlock_academia] All bypasses applied. App is unlocked.
```

Use a debugger or `log stream --predicate 'subsystem == "com.speetar.academia.app"'` to watch live.

## Defensive Recommendations

See `../for_edu_dylib_defense_report.md` and `../defensive_fail_closed_harness/` for:
- Runtime integrity checks (dyld scanning for unknown dylibs)
- Static obfuscation (class/selector name encryption)
- Server-side receipt validation (not client-side only)
- Fail-closed pattern (gate at Flutter AND native layers)

---

**For authorized educational/defensive testing only.**
