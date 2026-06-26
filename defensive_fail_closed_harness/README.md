# Defensive Fail-Closed Harness

This is a non-weaponized Flutter/Dart harness for validating fail-closed behavior around local screen-protection controls. It does not include dylibs, runtime hooks, re-signing steps, or bypass payloads.

## Purpose

Use this harness in a QA build or source-level test environment to verify that protected video playback fails closed when the local screen-protection boundary fails.

The tested behavior is:

- the protected video canvas starts obscured;
- playback is revealed only after screen protection succeeds;
- `enableScreenshotBlocking: failed to apply protection` is treated as a security failure;
- the active VdoCipher player handle is stopped and disposed;
- the session is forced into logout or revalidation;
- screenshot notifications are telemetry only and are not trusted as primary enforcement.

## Integration

Copy `lib/security_gate_controller.dart` and `lib/method_channel_screen_protection_client.dart` into the Flutter app or import them from a local package. Bind the controller to the app's VdoCipher player adapter and revalidation/logout flow.

For QA validation, inject a fake `ScreenProtectionClient` that returns:

```dart
const ScreenProtectionResult.failure(
  code: 'SCREEN_PROTECTION_FAILED',
  message: 'enableScreenshotBlocking: failed to apply protection',
);
```

Expected result: the video remains obscured, the player is terminated, and revalidation is required.

For iOS dev-mode validation with a real platform channel, add `ios/SecurityScreenProtectionBridge.swift` to the Runner target and follow `IOS_DEV_MODE_TEST.md`.

## Running The Tests

From this harness directory:

```bash
flutter test
```

If copied into the app's normal test tree, update the import path in the test file to match the project layout.
