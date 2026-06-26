# Validation Status

This note records the strongest safe validation performed in this workspace. No dylib, hook, re-signing helper, or bypass payload was created.

## Confirmed Binary Evidence

The following strings were found directly in the extracted iOS app bundle:

| File | Evidence | Offset |
|---|---|---:|
| `Payload/Runner.app/Frameworks/ScreenPreventerKit.framework/ScreenPreventerKit` | `enableScreenshotBlocking: failed to apply protection` | `0x16e00` |
| `Payload/Runner.app/Frameworks/ScreenPreventerKit.framework/ScreenPreventerKit` | `UIApplicationUserDidTakeScreenshotNotification` | `0x1c51b` |
| `Payload/Runner.app/Frameworks/ScreenPreventerKit.framework/ScreenPreventerKit` | `UIScreenCapturedDidChangeNotification` | `0x1c54d` |
| `Payload/Runner.app/Frameworks/ScreenPreventerKit.framework/ScreenPreventerKit` | `isPreventScreenshotEnabled` | `0x15e40` |
| `Payload/Runner.app/Frameworks/ScreenPreventerKit.framework/ScreenPreventerKit` | `isPreventScreenRecordingEnabled` | `0x15e60` |
| `Payload/Runner.app/Frameworks/safe_device.framework/safe_device` | `isJailBroken` | `0x6cb6` |
| `Payload/Runner.app/Frameworks/safe_device.framework/safe_device` | `isJailbroken` | `0x6cd6` |
| `Payload/Runner.app/Frameworks/safe_device.framework/safe_device` | `DYLD_INSERT_LIBRARIES` | `0x74bf` |
| `Payload/Runner.app/Frameworks/safe_device.framework/safe_device` | `/usr/sbin/frida-server` | `0x733a` |
| `Payload/Runner.app/Frameworks/App.framework/App` | `ScreenshotProtectionService` | `0x148ec20` |
| `Payload/Runner.app/Frameworks/App.framework/App` | `preventScreenshotOn` | `0x15d07f0` |
| `Payload/Runner.app/Frameworks/App.framework/App` | `preventScreenshotOff` | `0x15c9230` |
| `Payload/Runner.app/Frameworks/App.framework/App` | `_checkScreenRecording` | `0x13c0730` |
| `Payload/Runner.app/Frameworks/App.framework/App` | `Control screenshot permission for this video` | `0x1482ca0` |
| `Payload/Runner.app/Frameworks/App.framework/App` | `allowScreenshot` | `0x148a6a0` |

## Current Verdict

- Local-only screen and jailbreak protection surfaces: confirmed.
- Fail-open protection failure string: confirmed.
- Static bypass feasibility: plausible if app authorization depends on these local signals.
- Actual paid-content or DRM bypass: not proven in this workspace because no authorized iOS device session, test account, backend logs, or dynamic app execution is available.

## Required Dynamic Proof

To prove a real runtime bypass, run an authorized QA test where local screen/jailbreak signals are simulated as attacker-controlled while using a non-entitled account.

The bypass is confirmed only if the backend still issues protected course data, VdoCipher playback credentials, offline download tokens, or DRM licenses.

If the backend denies those requests regardless of local state, the issue remains a local hardening and fail-closed UI/content-protection finding, not a confirmed subscription or DRM authorization bypass.
