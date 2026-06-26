import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/method_channel_screen_protection_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.security/screen_protection');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps dev-mode screen-protection failure into fail-closed result',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enableScreenshotBlocking');
      expect(call.arguments, containsPair('qaForceFailure', true));
      return <String, Object?>{
        'ok': false,
        'code': 'SCREEN_PROTECTION_FAILED',
        'message': 'enableScreenshotBlocking: failed to apply protection',
        'logs': <String>[
          'QA dev-mode simulated ScreenPreventerKit failure',
        ],
      };
    });

    const client = MethodChannelScreenProtectionClient(qaForceFailure: true);

    final result = await client.enableScreenshotBlocking();

    expect(result.ok, isFalse);
    expect(result.code, 'SCREEN_PROTECTION_FAILED');
    expect(result.containsFailOpenSignal, isTrue);
  });

  test('null platform response is treated as failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    const client = MethodChannelScreenProtectionClient();

    final result = await client.enableScreenshotBlocking();

    expect(result.ok, isFalse);
    expect(result.code, 'NULL_PLATFORM_RESPONSE');
  });
}
