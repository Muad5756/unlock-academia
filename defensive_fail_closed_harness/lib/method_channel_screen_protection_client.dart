import 'package:flutter/services.dart';

import 'security_gate_controller.dart';

class MethodChannelScreenProtectionClient implements ScreenProtectionClient {
  static const MethodChannel _channel = MethodChannel(
    'app.security/screen_protection',
  );

  final bool qaForceFailure;

  const MethodChannelScreenProtectionClient({
    this.qaForceFailure = const bool.fromEnvironment(
      'SECURITY_QA_FORCE_SCREEN_PROTECTION_FAILURE',
    ),
  });

  @override
  Future<ScreenProtectionResult> enableScreenshotBlocking() async {
    final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'enableScreenshotBlocking',
      <String, Object?>{
        'qaForceFailure': qaForceFailure,
      },
    );

    if (response == null) {
      return const ScreenProtectionResult.failure(
        code: 'NULL_PLATFORM_RESPONSE',
        message: 'Screen protection platform channel returned null',
      );
    }

    final ok = response['ok'] == true;
    final message = response['message']?.toString();
    final logs = _readStringList(response['logs']);

    if (ok) {
      return ScreenProtectionResult.success(
        message: message,
        logs: logs,
      );
    }

    return ScreenProtectionResult.failure(
      code: response['code']?.toString() ?? 'SCREEN_PROTECTION_FAILED',
      message: message ?? 'Screen protection failed',
      logs: logs,
    );
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }
}
