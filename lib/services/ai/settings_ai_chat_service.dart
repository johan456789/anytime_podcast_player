import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';
import 'package:anytime/services/ai/mock_ai_chat_service.dart';
import 'package:anytime/services/ai/openai_chat_service.dart';
import 'package:anytime/services/settings/settings_service.dart';
import 'package:meta/meta.dart';

/// Selects the [AiChatService] to use for each request based on the user's
/// settings: when an API key and endpoint are configured the assistant talks
/// to the OpenAI compatible provider, otherwise it falls back to the
/// transcript grounded demo service.
///
/// Cancellation is forwarded to the delegate which produced the active reply
/// so that stopping generation also aborts the in-flight provider request.
class SettingsAiChatService extends AiChatService {
  final SettingsService settingsService;

  /// The delegate which produced the current reply, if any. Chat is
  /// single-flight (the bloc refuses asks while busy), so a single slot is
  /// sufficient.
  AiChatService? _activeDelegate;

  final MockAiChatService _mockService = MockAiChatService();

  SettingsAiChatService(this.settingsService);

  bool get isConfigured =>
      settingsService.aiChatEndpoint.trim().isNotEmpty && settingsService.aiChatApiKey.trim().isNotEmpty;

  /// Creates the provider-backed delegate. Exposed so tests can observe
  /// cancellation being forwarded to the active delegate.
  @visibleForTesting
  AiChatService createProviderService() => OpenAiChatService(
        endpoint: settingsService.aiChatEndpoint.trim(),
        apiKey: settingsService.aiChatApiKey.trim(),
        model: settingsService.aiChatModel.trim(),
      );

  @override
  Stream<String> send(AiChatRequest request) {
    if (isConfigured) {
      final delegate = createProviderService();

      _activeDelegate = delegate;

      return delegate.send(request);
    }

    /// Nothing in flight for the demo service to abort.
    _activeDelegate = null;

    return _mockService.send(request);
  }

  @override
  Future<void> cancel() async {
    await _activeDelegate?.cancel();
  }
}
