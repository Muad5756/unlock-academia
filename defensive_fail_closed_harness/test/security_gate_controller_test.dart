import 'package:flutter_test/flutter_test.dart';

import '../lib/security_gate_controller.dart';

void main() {
  test('screen protection failure obscures content and forces revalidation',
      () async {
    final screenProtection = _FakeScreenProtectionClient(
      const ScreenProtectionResult.failure(
        code: 'SCREEN_PROTECTION_FAILED',
        message: 'enableScreenshotBlocking: failed to apply protection',
      ),
    );
    final revalidation = _FakeRevalidationController();
    final telemetry = _FakeTelemetrySink();
    final player = _FakeProtectedVideoPlayerHandle();
    final controller = SecurityGateController(
      screenProtection: screenProtection,
      revalidation: revalidation,
      telemetry: telemetry,
    )..bindPlayer(player);

    final allowed = await controller.prepareForProtectedPlayback();

    expect(allowed, isFalse);
    expect(controller.isBlocked, isTrue);
    expect(controller.isObscured, isTrue);
    expect(controller.blockReason, SecurityBlockReason.screenProtectionFailed);
    expect(player.stopped, isTrue);
    expect(player.disposed, isTrue);
    expect(revalidation.called, isTrue);
    expect(
      telemetry.events.map((event) => event.name),
      contains('protected_playback_fail_closed'),
    );
  });

  test('successful screen protection allows protected playback reveal', () async {
    final controller = SecurityGateController(
      screenProtection: _FakeScreenProtectionClient(
        const ScreenProtectionResult.success(message: 'protection enabled'),
      ),
      revalidation: _FakeRevalidationController(),
      telemetry: _FakeTelemetrySink(),
    );

    final allowed = await controller.prepareForProtectedPlayback();

    expect(allowed, isTrue);
    expect(controller.state, SecurityGateState.ready);
    expect(controller.isObscured, isFalse);
    expect(controller.isBlocked, isFalse);
  });

  test('platform exception fails closed', () async {
    final revalidation = _FakeRevalidationController();
    final player = _FakeProtectedVideoPlayerHandle();
    final controller = SecurityGateController(
      screenProtection: _ThrowingScreenProtectionClient(),
      revalidation: revalidation,
      telemetry: _FakeTelemetrySink(),
    )..bindPlayer(player);

    final allowed = await controller.prepareForProtectedPlayback();

    expect(allowed, isFalse);
    expect(controller.isBlocked, isTrue);
    expect(controller.blockReason, SecurityBlockReason.screenProtectionException);
    expect(player.stopped, isTrue);
    expect(player.disposed, isTrue);
    expect(revalidation.called, isTrue);
  });

  test('screenshot notification is telemetry only', () {
    final telemetry = _FakeTelemetrySink();
    final controller = SecurityGateController(
      screenProtection: _FakeScreenProtectionClient(
        const ScreenProtectionResult.success(),
      ),
      revalidation: _FakeRevalidationController(),
      telemetry: telemetry,
    );

    controller.recordReactiveScreenshotNotification();

    expect(controller.state, SecurityGateState.obscured);
    expect(controller.isBlocked, isFalse);
    expect(
      telemetry.events.single.fields['enforcement'],
      'telemetry_only',
    );
  });
}

class _FakeScreenProtectionClient implements ScreenProtectionClient {
  final ScreenProtectionResult result;

  _FakeScreenProtectionClient(this.result);

  @override
  Future<ScreenProtectionResult> enableScreenshotBlocking() async => result;
}

class _ThrowingScreenProtectionClient implements ScreenProtectionClient {
  @override
  Future<ScreenProtectionResult> enableScreenshotBlocking() async {
    throw StateError('platform channel unavailable');
  }
}

class _FakeProtectedVideoPlayerHandle implements ProtectedVideoPlayerHandle {
  bool stopped = false;
  bool disposed = false;

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeRevalidationController implements RevalidationController {
  bool called = false;
  SecurityBlockReason? reason;
  String? details;

  @override
  Future<void> forceRevalidation({
    required SecurityBlockReason reason,
    String? details,
  }) async {
    called = true;
    this.reason = reason;
    this.details = details;
  }
}

class _FakeTelemetrySink implements SecurityTelemetrySink {
  final events = <_TelemetryEvent>[];

  @override
  void recordSecurityEvent(String name, Map<String, Object?> fields) {
    events.add(_TelemetryEvent(name, fields));
  }
}

class _TelemetryEvent {
  final String name;
  final Map<String, Object?> fields;

  _TelemetryEvent(this.name, this.fields);
}
