# iOS Dev-Mode Fail-Closed Test

This procedure validates fail-closed behavior without dylibs, runtime hooks, app re-signing, or bypass payloads. It uses a source-level QA flag in a debug build.

## Files

- `lib/security_gate_controller.dart`
- `lib/method_channel_screen_protection_client.dart`
- `ios/SecurityScreenProtectionBridge.swift`

## Flutter Wiring

Use the method-channel client in the protected playback path:

```dart
final securityGate = SecurityGateController(
  screenProtection: const MethodChannelScreenProtectionClient(),
  revalidation: appRevalidationController,
  telemetry: appTelemetrySink,
);
```

Before starting the VdoCipher player, call:

```dart
final allowed = await securityGate.prepareForProtectedPlayback();
if (!allowed) {
  return;
}
```

Bind the active player handle immediately after the player is created:

```dart
securityGate.bindPlayer(vdoCipherPlayerHandle);
```

## iOS Wiring

Add `SecurityScreenProtectionBridge.swift` to the iOS Runner target.

Register it from `AppDelegate.swift` after Flutter plugin registration. Supply your app's real ScreenPreventerKit adapter for normal operation. In debug QA mode, the bridge can simulate failure when Dart passes the QA flag.

```swift
if let registrar = self.registrar(forPlugin: "SecurityScreenProtectionBridge") {
    SecurityScreenProtectionBridge.register(
        with: registrar,
        adapter: realScreenProtectionAdapter
    )
}
```

If `adapter` is nil, the bridge returns `SCREEN_PROTECTION_ADAPTER_MISSING`, which should also fail closed.

## Run The Failure Test

Run the app in debug/dev mode with:

```bash
flutter run --debug --dart-define=SECURITY_QA_FORCE_SCREEN_PROTECTION_FAILURE=true
```

Expected result:

- `enableScreenshotBlocking` returns `ok: false`;
- the video canvas remains obscured;
- the active VdoCipher player is stopped and disposed;
- the user is forced into logout or revalidation;
- backend logs show no new protected token, download token, or DRM license issued after the failure.

## Run The Control Test

Run without the QA flag:

```bash
flutter run --debug
```

Expected result:

- if the real native adapter succeeds, protected playback can continue;
- if the native adapter fails or is missing, protected playback still fails closed.

## Pass / Fail

Pass:

- failure or missing native protection blocks playback immediately;
- video is obscured before and during failure handling;
- player termination occurs before revalidation completes;
- screenshot notifications are telemetry only.

Fail:

- protected video remains visible after the failure response;
- VdoCipher playback continues after protection failure;
- revalidation is not triggered;
- backend issues protected credentials after the fail-closed event.
