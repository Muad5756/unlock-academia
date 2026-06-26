# Academia (iOS) — Injection & Content‑Protection Threat Model

**Target:** `com.speetar.academia.app` (Academia by Speetar), v1.9.14, build 149 — Flutter / iOS (arm64)
**Artifact analysed:** decrypted IPA at `app/extracted/Payload/Runner.app/`
**Document type:** Defensive red‑team threat model (attacker‑perspective deep dive + paired defenses)
**Author scope:** Authorized self‑analysis for hardening. Date: 2026‑06‑26.

> **Posture / responsible‑use note.** This document explains attacker *tactics, techniques and procedures (TTPs)* at a conceptual level and maps them to this app's real code surface so the team can prioritize hardening. Consistent with the workspace's existing `defensive_fail_closed_harness/` convention, it contains **no turnkey bypass payloads, no ready‑to‑run hook scripts targeting this app's offsets, and no step‑by‑step "pirate this app" recipe.** The actionable depth lives in *detection and defense*. Any dynamic testing must be performed only on devices and accounts you are authorized to use.

---

## 1. Executive Summary

An attacker who wants (A) **free access to paid courses** and (B) **the ability to screen‑record protected video** will treat this app as a classic *client‑side trust* target. The decisive fact is that **every protection currently shipped is a local‑device signal** — jailbreak checks, Frida/`DYLD_INSERT_LIBRARIES` string checks, and screenshot/recording blockers all run on the attacker's own hardware, which they fully control.

The realistic attack is a **dylib‑injection kill‑chain**: take the (already decrypted) IPA → add a malicious dynamic library via a load command → re‑sign with a free developer certificate → sideload → at runtime, hook the named protection functions so they always return the "safe" answer. On a jailbroken device the same hooks are applied live with Frida/Objection without re‑signing.

Whether that actually yields **free content** depends entirely on one unverified question: **does the backend re‑check entitlement server‑side before issuing VdoCipher playback/download tokens, or does it trust the client?** If it trusts the client, the bypass is total. If it does not, client hooks only defeat the *UI/playback gate* and the residual content‑theft risk collapses to **screen capture of legitimately‑entitled sessions**.

**Headline weaknesses that make the chain easy (all confirmed in the bundle):**

| # | Weakness | Why it helps the attacker |
|---|----------|---------------------------|
| 1 | **No anti‑debugging** (no `ptrace(PT_DENY_ATTACH)`, no `sysctl` `P_TRACED` check) | LLDB/Frida attach freely; dynamic analysis is unobstructed. |
| 2 | **Symbols not stripped, strings in plaintext** | Protection function names (`enableScreenshotBlocking`, `_checkScreenRecording`, `isJailBroken`) are a ready‑made hook list. |
| 3 | **Detection is string/path‑based** (`safe_device`) | Brittle; trivially defeated by renamed tooling or by hooking the check itself. |
| 4 | **`NSAllowsArbitraryLoads = true`** (`Info.plist`) | No App Transport Security baseline → API interception/MITM is easy; suggests no certificate pinning. |
| 5 | **Hardcoded `SECRET_KEY` + live 3rd‑party keys** in `.env.prod` | If the key signs API requests, the attacker can forge valid signatures. |
| 6 | **Server‑side entitlement enforcement unproven** | The single factor that decides whether any of the above yields *free content*. |

**Overall resilience rating: LOW–MEDIUM.** The cryptographic content protection (FairPlay via VdoCipher) is strong, but the *resilience layer* (MASVS‑RESILIENCE) that is supposed to protect it on a hostile device is thin and uniformly local‑trust.

---

## 2. Target Profile & Attack‑Surface Map

### 2.1 Stack and trust boundaries

- **Engine:** Flutter. Dart business logic is AOT‑compiled into `Payload/Runner.app/Frameworks/App.framework/App` (a Mach‑O). Native glue and the Flutter engine sit in `Flutter.framework`; the launcher is `Payload/Runner.app/Runner`.
- **Implication for attackers:** Dart AOT is *harder* to read than Objective‑C/Swift (no `class-dump`), but the **Objective‑C/Swift frameworks** (screen protection, jailbreak detection, RevenueCat, VdoCipher) expose clean ObjC selectors and symbols and are the natural hooking surface. The Dart↔native boundary is a **Flutter `MethodChannel`** (e.g. `app.security/screen_protection` seen in `SecurityScreenProtectionBridge.swift`), and method channels are a high‑value interception point because they carry plaintext, structured messages.

### 2.2 Security‑relevant frameworks (what each guards)

| Framework / binary | Role | Notable symbols (plaintext in binary) |
|---|---|---|
| `safe_device.framework` | Jailbreak + injection + emulator checks | `isJailBroken`, `DYLD_INSERT_LIBRARIES` (`0x74bf`), `/usr/sbin/frida-server` (`0x733a`) |
| `DTTJailbreakDetection.framework` | Dedicated jailbreak detection | — |
| `ScreenPreventerKit.framework` | Screenshot/recording blocking | `isPreventScreenshotEnabled` (`0x15e40`), `isPreventScreenRecordingEnabled` (`0x15e60`), `enableScreenshotBlocking: failed to apply protection` (`0x16e00`), `UIScreenCapturedDidChangeNotification` (`0x1c54d`) |
| `ScreenProtectorKit.framework`, `screen_protector.framework` | Additional screen protection | — |
| `App.framework/App` | App logic glue to protection | `ScreenshotProtectionService` (`0x148ec20`), `preventScreenshotOn/Off`, `_checkScreenRecording` (`0x13c0730`), `allowScreenshot`, `Control screenshot permission for this video` |
| `vdocipher_flutter.framework` | DRM video (FairPlay) | — |
| `RevenueCat.framework` / `purchases_flutter.framework` | Subscriptions / entitlements | — |

### 2.3 Exposed secrets inventory (`App.framework/.../flutter_assets/.env.prod`)

```
APP_ENV=production
BASE_URL=https://system.academia.education/
SECRET_KEY=a463c0cd-78ed-4bda-a5f6-f70c3e597dfb     ← shipped in the client
VERIFY_USER_URL=https://academia.speetar.com/login-verify-users
AGORA_APP_ID=2e66a5f41b2f4200babc3e87b64efa39
ONESIGNAL_APP_ID=829c8900-263a-41a0-a5bb-05467440b223
STRIPE_BASE_URL=https://api.stripe.com/v1
REAL_DEVICE_CHECK=true                               ← positive: DeviceCheck in use
PUSHER_API_KEY=26e19ae94a3d45f105be
PUSHER_CLUSTER=ap2
PUSHER_AUTH_ENDPOINT=https://system.academia.education/api/pusher/auth
```

A `.env` bundled in `flutter_assets` is **plaintext** and extractable by anyone with the IPA. Treat every value here as *public*. The `SECRET_KEY` is the most dangerous: if the backend uses it to validate request signatures/HMACs, that control is void because the attacker holds the key. (`REAL_DEVICE_CHECK=true` is a genuine positive — see §7.)

---

## 3. Attacker Model & Prerequisites

Two operating modes cover essentially all real‑world attempts:

**Mode A — Non‑jailbroken (re‑sign + sideload).** The attacker patches the app to load an extra dylib, re‑signs with a **free 7‑day Apple developer certificate**, and sideloads via AltStore / Sideloadly, or installs on a TrollStore/eSign‑capable device. No jailbreak required. This is the **mass‑distribution piracy** path because the resulting "modded IPA" can be shared.

**Mode B — Jailbroken device (live instrumentation).** The attacker runs the unmodified app and attaches a dynamic instrumentation toolkit (Frida server, Objection) or installs a tweak via a hooking runtime (Cydia Substrate / Substitute / ElleKit). No re‑sign needed; fastest for *research and recipe development*, which then feeds Mode A.

**Starting materials / skill tiers.**
- *Step‑zero is already done for the attacker:* the artifact in `app/extracted/` is a **decrypted** build (filename `…-dycryption.ipa`). App Store binaries are FairPlay‑encrypted at rest; an attacker normally must decrypt first (run on a jailbroken device and dump from memory). A decrypted build leaking publicly removes that barrier entirely.
- *Low skill:* point‑and‑click sideload tools with a "tweak/dylib inject" checkbox.
- *Medium skill:* writing Frida/Objection hooks against the readable symbols.
- *High skill:* defeating DRM token issuance, request‑signature forgery, automated tooling.

---

## 4. The Injection Kill‑Chain (deep dive)

The stages below describe *how the technique works in general* and *which part of this app each stage targets*. They are intentionally conceptual — no app‑specific commands or payloads.

### 4.1 Acquire & decrypt the IPA
App Store apps ship encrypted (the Mach‑O `LC_ENCRYPTION_INFO` `cryptid` flag). Attackers obtain a decrypted copy by running on a jailbroken device and dumping the decrypted pages from memory (the well‑known class of "IPA dumper" tools). **For this target the work is already done** — a decrypted build exists in the workspace. *Defensive takeaway: a leaked decrypted build is a serious incident because it removes the single biggest speed bump; treat build artifacts as sensitive.*

### 4.2 Static reconnaissance — building the hook list
With a decrypted Mach‑O, the attacker enumerates the attack surface:
- `strings` / `nm` / `otool -l` reveal load commands, linked libraries, and — because **symbols are not stripped here** — human‑readable function names.
- Disassemblers (Hopper, Ghidra, IDA) and `class-dump` recover ObjC class/selector layouts.
- The plaintext strings in §2.2 effectively *publish the defense's own API*: `enableScreenshotBlocking`, `isPreventScreenRecordingEnabled`, `_checkScreenRecording`, `allowScreenshot`, `isJailBroken`. An attacker reads this list and immediately knows what to neutralize.
- The Flutter `MethodChannel` name `app.security/screen_protection` tells them exactly where the Dart↔native security conversation happens.

### 4.3 What a "malicious dylib" actually is
A dynamic library that the loader (`dyld`) maps into the app's address space at launch, with code that runs inside the app's process and rewrites behavior. The common building blocks:
- **ObjC method swizzling** — exchange a method's implementation so a security selector (e.g. a jailbreak/recording check) returns the attacker's preferred value. Easy precisely because ObjC dispatch is dynamic and the selectors are named.
- **`fishhook`‑style symbol rebinding** — re‑point C function symbols (e.g. low‑level checks) to attacker code.
- **Frida Gadget** — an embedded library that exposes the whole process to a scripting engine; the attacker iterates on hooks without recompiling.
- **Theos/`logos` tweak** — the jailbreak‑ecosystem way to package the same hooks as a `.dylib`.

### 4.4 Insertion — getting the dylib loaded
- **Mode A (sideload):** add an `LC_LOAD_DYLIB` (or `LC_LOAD_WEAK_DYLIB`) load command to the `Runner` Mach‑O so `dyld` loads the attacker's library before app code runs (the function performed by tools such as `insert_dylib`/`optool`, and by the "inject dylib" toggle in sideload utilities). The library is copied into the app bundle (typically under `Frameworks/`).
- **Mode B (jailbreak):** the `DYLD_INSERT_LIBRARIES` environment‑variable path, or a Substrate/ElleKit tweak loaded into targeted processes. (Note: `safe_device` only *string‑checks* for `DYLD_INSERT_LIBRARIES`; see §6/§7 for why a string check is weak.)

### 4.5 Re‑sign & sideload (Mode A)
A modified Mach‑O invalidates Apple's signature, so the attacker re‑signs the bundle and its embedded dylib with their own (often free) certificate and a matching provisioning profile, then installs via sideload tooling. Because protection is local, the freshly installed mod can immediately run the §4.2 hook list.

### 4.6 Live instrumentation (Mode B)
On a jailbroken device the attacker skips re‑signing: attach Frida to the running process and apply hooks interactively, or use Objection's prebuilt helpers for common iOS controls (jailbreak‑bypass, pinning‑bypass). This is the fastest loop for *developing* a bypass, which is then frozen into a Mode‑A modded IPA for distribution.

**Net effect of the chain:** the attacker now executes code *inside* the app and can make any local check answer however they like. Everything in §5 and §6 follows from this single capability.

---

## 5. Goal A — "Free Courses" (entitlement / DRM bypass)

For each vector: the mechanism, and **"does it actually yield content?"**

### 5.1 Hooking the client‑side entitlement decision
RevenueCat exposes entitlement state to the app (the `CustomerInfo` / "active entitlements" model) which the UI uses to decide `isPro` / `hasAccess` / unlock state. An injected dylib can force these accessors to report "subscribed," flipping the UI to the unlocked state and removing paywalls.
**Yields content?** *Only if the backend trusts the client.* If course media/tokens are gated **server‑side** on the real subscription, a forced‑true client shows unlocked UI but the media requests still fail. This is why §5.4 is decisive. (RevenueCat's own guidance is that entitlements must be verified server‑side for exactly this reason.)

### 5.2 API‑layer entitlement forgery / response tampering (MITM)
With `NSAllowsArbitraryLoads = true` and no evidence of certificate pinning, an attacker proxying the device can read and **modify** the JSON of entitlement/profile API responses (e.g. flip a `is_subscribed`/`plan`/`access` field) before the app sees them. If the app trusts response bodies, this unlocks features without touching the binary.
**Compounding risk — `SECRET_KEY`:** if `system.academia.education` authenticates requests with an HMAC/signature derived from the bundled `SECRET_KEY`, the attacker can compute valid signatures for *forged* requests, defeating that control outright.
**Yields content?** Same dependency as §5.1 — it works to the extent the server trusts client‑supplied state.

### 5.3 VdoCipher / FairPlay reality check
VdoCipher on iOS uses **Apple FairPlay**, hardware‑backed DRM: the content decryption key is delivered as a license to the Secure processing path and decrypted frames are handled in a protected pipeline. Practical consequences:
- **Pulling the raw decrypted video stream is hard** — this is the strong part of the design and not the soft target.
- The realistic attacker paths are therefore: **(a) capture the *rendered output*** (→ Goal B, §6), and **(b) abuse the *token/license issuance*** — replaying or obtaining playback OTPs and **offline download licenses** for content the account is not entitled to.

### 5.4 The decisive backstop — server‑side token issuance
VdoCipher playback requires the **backend** to mint a short‑lived OTP/`playbackInfo`; offline viewing requires a download token + persistent license. **The whole of §5 hinges on whether `system.academia.education` verifies the user's entitlement *before* issuing these.**
- If **yes** (server checks the authoritative subscription record, ignores client claims): client hooks and response‑tampering do **not** yield content; risk drops to screen capture (§6).
- If **no** (server issues tokens on a client‑asserted flag): the bypass is complete and scalable.

This is exactly the open question recorded in `defensive_fail_closed_harness/VALIDATION_STATUS.md` ("Actual paid‑content or DRM bypass: not proven … because no authorized backend logs"). **Resolving it is the highest‑value action in this report** (see §7.1 / §8).

### 5.5 Offline‑download token abuse
Downloaded courses store a persistent FairPlay license locally. Attack interest centers on: requesting download tokens for non‑entitled content (a §5.4 server‑trust problem), and the lifetime/binding of the persistent license (can it be moved or its expiry ignored?). Defense: bind download tokens to a server‑verified entitlement and a device identity, keep licenses short‑lived and renew online.

---

## 6. Goal B — Screen Recording / Content Capture

Even with perfect entitlement enforcement, a *paying* attacker can try to exfiltrate the video by capturing what's on screen. This is where the `ScreenPreventer/Protector` stack matters — and where its local‑only nature bites.

### 6.1 How the screen protection works (and its exact hook points)
- **Screenshot/recording blocking** on iOS is typically implemented with the **secure‑`UITextField` layer trick**: protected content is hosted inside a view backed by a `UITextField` whose `isSecureTextEntry` is true, so iOS excludes it from screenshots and the screen‑recording/mirroring buffer (it renders blank in captures). `ScreenPreventerKit`'s `isPreventScreenshotEnabled` / `isPreventScreenRecordingEnabled` gate this.
- **Recording *detection*** uses `UIScreen.isCaptured` and the `UIScreenCapturedDidChangeNotification` observer (both present as strings); the app's `_checkScreenRecording` / `ScreenshotProtectionService` react to it; `UIApplicationUserDidTakeScreenshotNotification` is the (reactive, after‑the‑fact) screenshot signal.
- **Per‑video policy:** `allowScreenshot` and `Control screenshot permission for this video` show the app can toggle protection per content item.

**Attacker's move:** because all of these are named, local functions, an injected dylib simply forces them to the permissive branch — `isPreventScreenRecordingEnabled → false`, `allowScreenshot → true`, or neutralizes the `isCaptured` observer so the app never reacts. The secure‑field layer can also be stripped by hooking the view setup.

### 6.2 The fail‑open string is the prize — and the existing harness is the right answer
The string `enableScreenshotBlocking: failed to apply protection` (`ScreenPreventerKit` `0x16e00`) reveals a path where protection *fails to apply*. If the app historically **continued playback on that failure (fail‑open)**, an attacker only needs to *force the failure* to get an unprotected, recordable video surface — no need to defeat the secure layer itself.

This is precisely what the workspace's `defensive_fail_closed_harness/` neutralizes: `SecurityGateController.prepareForProtectedPlayback()` treats `!result.ok` **or** the presence of that failure string (`containsFailOpenSignal`) as a security failure, keeps the canvas **obscured**, **stops and disposes** the VdoCipher player handle, and **forces revalidation/logout** — and it correctly classifies the screenshot notification as *telemetry only* (reactive, not preventive). **Ship this gate on the real protected‑playback path** so "make protection fail" stops being a win. (Caveat: a dylib that hooks the gate's *inputs* can still feed it a forged `success`; §7 addresses raising that bar.)

### 6.3 Out‑of‑band capture — the irreducible residual risk
No in‑app software control can stop **AirPlay/HDMI mirroring to a capture device** (mitigated only partially by `isCaptured`‑style external‑display detection) or a **second camera filming the screen**. These defeat every software protection by definition. The realistic mitigation is **deterrence and traceability**, not prevention: **forensic/session watermarking** (visible + invisible, bound to user/session) so leaked footage is traceable to an account.

### 6.4 Jailbroken capture tweaks
On a jailbroken device, system‑level screen‑record tweaks capture the framebuffer beneath the app's controls; the secure‑field trick is less reliable there. This collapses into the §7 jailbreak‑resilience problem.

---

## 7. Defenses (concise, per‑vector)

Mapped to OWASP **MASVS** (v2) categories. Priority order in §8.

### 7.1 Enforce entitlement server‑side (defeats §5.1, §5.2, §5.5) — *highest value*  · MASVS‑AUTH, MASVS‑CODE
Never issue VdoCipher OTP/`playbackInfo`, download tokens, or course payloads based on a client‑asserted flag. The backend must look up the authoritative subscription/purchase record (validate the App Store/RevenueCat receipt server‑to‑server) on **every** issuance. Make `isPro` in the client a *cosmetic* hint only. This single control makes most binary hooks irrelevant.

### 7.2 Kill the network‑tampering surface (defeats §5.2) · MASVS‑NETWORK‑1/2
Remove `NSAllowsArbitraryLoads` (scope ATS exceptions to specific hosts only if truly required) and add **certificate/public‑key pinning** to `system.academia.education` and the token endpoints. Pin in native code, not Dart, and fail closed on mismatch.

### 7.3 Remove client secrets / strengthen request auth (defeats §5.2 forgery) · MASVS‑STORAGE‑1, MASVS‑CRYPTO
Treat the shipped `SECRET_KEY` and all `.env.prod` keys as **burned** — rotate them. Do not ship long‑lived signing secrets in the bundle; derive per‑session credentials from an authenticated login + device attestation, and keep server‑side authorization independent of any client‑held secret.

### 7.4 Anti‑debugging (raises cost of all dynamic work) · MASVS‑RESILIENCE‑4
Add `ptrace(PT_DENY_ATTACH)` and a `sysctl`/`P_TRACED` self‑inspection (and, ideally, a direct‑`syscall` variant so the check itself isn't a single hookable libc call). Detect a tracer and fail closed. *Illustrative pattern (defensive):*
```c
// Conceptual — detect/deny debugger; combine several independent checks.
#include <sys/sysctl.h>
static bool being_traced(void) {
    struct kinfo_proc info; size_t size = sizeof(info);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    sysctl(mib, 4, &info, &size, NULL, 0);
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}
```

### 7.5 Detect injection by *state*, not by *string* (defeats §4.4 detection bypass) · MASVS‑RESILIENCE‑1/2
String‑matching `"DYLD_INSERT_LIBRARIES"` / `"/usr/sbin/frida-server"` (as `safe_device` does) is brittle. Instead enumerate the **actual loaded images** at runtime (`_dyld_image_count` / `_dyld_get_image_name`) and flag libraries loaded from outside the app bundle / system paths; detect extra `LC_LOAD_DYLIB` entries vs. a known‑good manifest; scan for instrumentation artifacts behaviorally (e.g. unexpected listening ports/named pipes, trampolines in critical prologues) rather than by fixed paths.

### 7.6 Harden the binary (raises §4.2 recon cost) · MASVS‑RESILIENCE‑3
**Strip symbols** from release builds; **encrypt/obfuscate the security strings** so the protection API isn't a free roadmap; obfuscate the most sensitive native control flow. Move security‑critical decisions out of easily‑swizzled ObjC selectors where feasible.

### 7.7 Make the screen‑protection gate tamper‑evident (defends §6) · MASVS‑RESILIENCE‑2
Ship the `defensive_fail_closed_harness` gate on the real playback path. Then raise the bar on its *inputs*: cross‑check `UIScreen.isCaptured` from multiple code sites, verify the secure‑field layer is actually installed (don't trust a single boolean), and treat a forced‑success that disagrees with an independent signal as tampering → fail closed. Keep watermarking (§7.9) as the backstop for §6.3.

### 7.8 Layer & diversify jailbreak/integrity checks (defends §4.6, §6.4) · MASVS‑RESILIENCE‑1
Combine `DTTJailbreakDetection`/`safe_device` with independent, inlined checks; verify the app's own **code signature/integrity** at runtime (e.g. validate the embedded signature and that critical frameworks load from the bundle). Assume any single check will be bypassed; redundancy + server‑side reaction (revoke session) is what matters.

### 7.9 Forensic watermarking (only real mitigation for §6.3) · MASVS‑RESILIENCE‑2
Bind a per‑user/per‑session visible + invisible watermark into the rendered video so any captured footage — even by camera — is traceable to an account, enabling deterrence and account action.

### 7.10 Device binding & attestation (raises §5.x cost) · MASVS‑AUTH
`REAL_DEVICE_CHECK=true` indicates Apple **DeviceCheck** is already in use — good. Strengthen to **App Attest** (hardware‑backed app integrity attestation) and bind issued tokens/licenses to the attested device so forged or shared sessions are rejected server‑side.

### 7.11 Consider commercial RASP · MASVS‑RESILIENCE (all)
For a content business at this scale, a runtime app self‑protection / mobile‑hardening SDK (e.g. the category including Guardsquare/DexGuard‑iXGuard, Appdome, Promon) consolidates anti‑debug, anti‑hook, anti‑tamper, jailbreak detection, and string/code obfuscation with ongoing updates against new tooling.

---

## 8. Prioritized Remediation Table

| Pri | Gap | Vectors closed | Fix | Effort | MASVS |
|----:|-----|----------------|-----|:------:|-------|
| **P0** | Server trusts client entitlement (unverified) | §5.1, §5.2, §5.5 | Verify subscription/receipt server‑side before issuing every token/payload | M (backend) | AUTH, CODE |
| **P0** | `NSAllowsArbitraryLoads=true`, no pinning | §5.2 | Remove ATS bypass; add native cert pinning, fail closed | S–M | NETWORK |
| **P0** | `SECRET_KEY` + keys in `.env.prod` | §5.2 forgery | Rotate keys; stop shipping signing secrets; per‑session creds | S–M | STORAGE, CRYPTO |
| **P1** | Fail‑open screen protection | §6.1, §6.2 | Ship `SecurityGateController` fail‑closed gate on real path | S (exists) | RESILIENCE‑2 |
| **P1** | No anti‑debugging | §4.x dynamic | `ptrace`/`sysctl`/syscall checks, fail closed | S | RESILIENCE‑4 |
| **P1** | String‑based injection detection | §4.4 | Inspect loaded `dyld` images & load commands; behavioral Frida detection | M | RESILIENCE‑1/2 |
| **P2** | Readable symbols/strings | §4.2 | Strip symbols; encrypt security strings; obfuscate critical paths | M | RESILIENCE‑3 |
| **P2** | Single‑layer jailbreak/integrity | §4.6, §6.4 | Redundant checks + runtime code‑signature validation | M | RESILIENCE‑1 |
| **P2** | Camera/AirPlay capture (irreducible) | §6.3 | Per‑session forensic watermarking | M | RESILIENCE‑2 |
| **P3** | Device binding strength | §5.x | Upgrade DeviceCheck → App Attest; bind tokens to device | M | AUTH |
| **P3** | Maintenance burden of bespoke controls | all | Evaluate commercial RASP/hardening SDK | L | RESILIENCE |

---

## 9. Appendix

### 9.1 Confirmed binary evidence (from `defensive_fail_closed_harness/VALIDATION_STATUS.md`)

| File | Evidence string | Offset |
|---|---|---:|
| `ScreenPreventerKit.framework/ScreenPreventerKit` | `enableScreenshotBlocking: failed to apply protection` | `0x16e00` |
| `ScreenPreventerKit.framework/ScreenPreventerKit` | `UIApplicationUserDidTakeScreenshotNotification` | `0x1c51b` |
| `ScreenPreventerKit.framework/ScreenPreventerKit` | `UIScreenCapturedDidChangeNotification` | `0x1c54d` |
| `ScreenPreventerKit.framework/ScreenPreventerKit` | `isPreventScreenshotEnabled` | `0x15e40` |
| `ScreenPreventerKit.framework/ScreenPreventerKit` | `isPreventScreenRecordingEnabled` | `0x15e60` |
| `safe_device.framework/safe_device` | `isJailBroken` | `0x6cb6` |
| `safe_device.framework/safe_device` | `DYLD_INSERT_LIBRARIES` | `0x74bf` |
| `safe_device.framework/safe_device` | `/usr/sbin/frida-server` | `0x733a` |
| `App.framework/App` | `ScreenshotProtectionService` | `0x148ec20` |
| `App.framework/App` | `preventScreenshotOn` | `0x15d07f0` |
| `App.framework/App` | `preventScreenshotOff` | `0x15c9230` |
| `App.framework/App` | `_checkScreenRecording` | `0x13c0730` |
| `App.framework/App` | `Control screenshot permission for this video` | `0x1482ca0` |
| `App.framework/App` | `allowScreenshot` | `0x148a6a0` |

Config evidence: `Info.plist` lines 177–182 (`NSAppTransportSecurity` → `NSAllowsArbitraryLoads=true`, `NSAllowsArbitraryLoadsInWebContent=true`); `.env.prod` (secrets, §2.3).

### 9.2 References
- **OWASP MASVS v2** — categories used above (AUTH, NETWORK, STORAGE, CRYPTO, CODE, **RESILIENCE‑1..4**).
- **OWASP MASTG** — iOS test topics: anti‑debugging detection, reverse‑engineering‑tools detection (Frida/Substrate), jailbreak detection, file/code‑integrity checks, network certificate pinning.
- Apple: FairPlay Streaming, DeviceCheck & **App Attest** (`DCAppAttestService`), App Transport Security.
- VdoCipher & RevenueCat: server‑side token issuance / receipt validation guidance.

### 9.3 Glossary
- **dylib** — dynamic library loaded into a process by `dyld`; the injection vehicle.
- **`LC_LOAD_DYLIB`** — Mach‑O load command instructing `dyld` to load a library at launch.
- **method swizzling** — swapping an Objective‑C method's implementation at runtime.
- **fishhook** — technique to rebind C symbols in a Mach‑O at runtime.
- **Frida / Objection** — dynamic instrumentation toolkit and its iOS automation layer.
- **FairPlay** — Apple's hardware‑backed content DRM (used by VdoCipher on iOS).
- **ATS** — App Transport Security; iOS network‑security baseline.
- **RASP** — Runtime Application Self‑Protection.
- **fail‑closed / fail‑open** — on a control failure, deny (closed) vs. allow (open) the protected action.

---

## 10. Responsible‑Use Note
This is an authorized, defense‑oriented threat model for the app's own team. It deliberately contains no weaponized payloads, no app‑specific bypass scripts, and no piracy walkthrough. Validate the §5.4 server‑side question and the P0 items first — they determine whether the rest of the surface matters. Conduct any dynamic confirmation only on authorized test devices and accounts, per `IOS_DEV_MODE_TEST.md`.
