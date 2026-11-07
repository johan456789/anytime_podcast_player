import 'package:anytime/services/settings/mobile_settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the secure storage of the AI provider API key: the key must
/// never be written to ordinary preferences and any plaintext copy left by
/// earlier builds must be migrated out.
void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final secureStore = <String, String>{};
  final secureWrites = <String>[];

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    secureStore.clear();
    secureWrites.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'read':
          return secureStore[call.arguments['key'] as String];
        case 'write':
          final key = call.arguments['key'] as String;
          final value = call.arguments['value'] as String;

          secureStore[key] = value;
          secureWrites.add(key);

          return null;
        case 'delete':
          secureStore.remove(call.arguments['key'] as String);

          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('api key is written to secure storage, not preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MobileSettingsService.resetForTest();
    final service = await MobileSettingsService.instance();

    service?.aiChatApiKey = 'sk-live-key';
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(secureStore['aiChatApiKey'], 'sk-live-key');
    expect(secureWrites, contains('aiChatApiKey'));

    /// The plaintext preferences copy must not reappear.
    final prefs = SharedPreferences.getInstance();
    expect(await prefs.then((p) => p.getString('aiChatApiKey')), isNull);
    expect(service?.aiChatApiKey, 'sk-live-key');
  });

  test('a plaintext key from an earlier build is migrated to secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'aiChatApiKey': 'sk-legacy-key'});
    secureStore.clear();
    MobileSettingsService.resetForTest();

    /// Start-up runs the migration: the legacy plaintext key moves to secure
    /// storage and is removed from preferences.
    final service = await MobileSettingsService.instance();

    expect(secureStore['aiChatApiKey'], 'sk-legacy-key');
    expect(await SharedPreferences.getInstance().then((p) => p.getString('aiChatApiKey')), isNull);
    expect(service?.aiChatApiKey, 'sk-legacy-key');
  });

  test('clearing the key removes it from secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MobileSettingsService.resetForTest();
    final service = await MobileSettingsService.instance();

    service?.aiChatApiKey = 'sk-to-clear';
    await Future<void>.delayed(const Duration(milliseconds: 50));

    service?.aiChatApiKey = '';
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(secureStore.containsKey('aiChatApiKey'), isFalse);
    expect(service?.aiChatApiKey, '');
  });
}
