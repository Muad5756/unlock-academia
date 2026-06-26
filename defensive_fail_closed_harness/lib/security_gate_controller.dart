import 'dart:async';

enum SecurityBlockReason {
  screenProtectionFailed,
  screenProtectionException,
  platformTimeout,
  localTamperSignal,
  revalidationRequired,
}

enum SecurityGateState {
  obscured,
  ready,
  blocked,
}

class ScreenProtectionResult {
  final bool ok;
  final String? code;
  final String? message;
  final List<String> logs;

  const ScreenProtectionResult.success({
    this.message,
    this.logs = const [],
  })  : ok = true,
        code = null;

  const ScreenProtectionResult.failure({
    required this.code,
    required this.message,
    this.logs = const [],
  }) : ok = false;

  bool get containsFailOpenSignal {
    final values = <String>[
      if (code != null) code!,
      if (message != null) message!,
      ...logs,
    ];

    return values.any(
      (value) => value.contains(
        'enableScreenshotBlocking: failed to apply protection',
      ),
    );
  }
}

abstract class ScreenProtectionClient {
  Future<ScreenProtectionResult> enableScreenshotBlocking();
}

abstract class ProtectedVideoPlayerHandle {
  Future<void> stop();
  Future<void> dispose();
}

abstract class RevalidationController {
  Future<void> forceRevalidation({
    required SecurityBlockReason reason,
    String? details,
  });
}

abstract class SecurityTelemetrySink {
  void recordSecurityEvent(String name, Map<String, Object?> fields);
}

class SecurityGateController {
  final ScreenProtectionClient screenProtection;
  final RevalidationController revalidation;
  final SecurityTelemetrySink telemetry;
  final Duration platformTimeout;

  SecurityGateState _state = SecurityGateState.obscured;
  SecurityBlockReason? _blockReason;
  String? _blockDetails;
  ProtectedVideoPlayerHandle? _player;

  SecurityGateController({
    required this.screenProtection,
    required this.revalidation,
    required this.telemetry,
    this.platformTimeout = const Duration(seconds: 2),
  });

  SecurityGateState get state => _state;
  bool get isObscured => _state != SecurityGateState.ready;
  bool get isBlocked => _state == SecurityGateState.blocked;
  SecurityBlockReason? get blockReason => _blockReason;
  String? get blockDetails => _blockDetails;

  void bindPlayer(ProtectedVideoPlayerHandle player) {
    _player = player;
  }

  Future<bool> prepareForProtectedPlayback() async {
    _setObscured();

    try {
      final result = await screenProtection
          .enableScreenshotBlocking()
          .timeout(platformTimeout);

      if (!result.ok || result.containsFailOpenSignal) {
        await failClosed(
          SecurityBlockReason.screenProtectionFailed,
          details: _formatFailure(result),
        );
        return false;
      }

      _state = SecurityGateState.ready;
      _blockReason = null;
      _blockDetails = null;
      telemetry.recordSecurityEvent('screen_protection_ready', {
        'message': result.message,
      });
      return true;
    } on TimeoutException catch (error) {
      await failClosed(
        SecurityBlockReason.platformTimeout,
        details: error.toString(),
      );
      return false;
    } catch (error) {
      await failClosed(
        SecurityBlockReason.screenProtectionException,
        details: error.toString(),
      );
      return false;
    }
  }

  Future<void> failClosed(
    SecurityBlockReason reason, {
    String? details,
  }) async {
    _state = SecurityGateState.blocked;
    _blockReason = reason;
    _blockDetails = details;

    telemetry.recordSecurityEvent('protected_playback_fail_closed', {
      'reason': reason.name,
      'details': details,
    });

    final player = _player;
    _player = null;

    if (player != null) {
      try {
        await player.stop();
      } finally {
        await player.dispose();
      }
    }

    await revalidation.forceRevalidation(
      reason: reason,
      details: details,
    );
  }

  void recordReactiveScreenshotNotification() {
    telemetry.recordSecurityEvent('ios_screenshot_notification_observed', {
      'enforcement': 'telemetry_only',
      'note': 'UIApplicationUserDidTakeScreenshotNotification is reactive',
    });
  }

  void _setObscured() {
    _state = SecurityGateState.obscured;
  }

  String _formatFailure(ScreenProtectionResult result) {
    final parts = <String>[
      if (result.code != null) result.code!,
      if (result.message != null) result.message!,
      ...result.logs,
    ];
    return parts.join(' | ');
  }
}
