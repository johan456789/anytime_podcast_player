import 'dart:async';
import 'dart:convert';

import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

/// An [AiChatService] backed by any OpenAI compatible chat completions
/// endpoint (OpenAI, Groq, Ollama, LM Studio, ...).
///
/// Replies are streamed as server sent events and are instructed to cite
/// transcript positions using `[mm:ss]` timestamps which the UI renders as
/// tappable seek chips.
class OpenAiChatService extends AiChatService {
  static const recentContextWindow = Duration(minutes: 5);

  /// Transcript budget in characters (~4 chars per token) before the context
  /// is reduced to the recent window plus keyword matches.
  static const transcriptCharacterBudget = 120000;

  /// Budget for the keyword match section of an abridged prompt, so a broad
  /// question cannot push the request over the model's context window.
  static const keywordMatchCharacterBudget = 30000;

  /// Budget for the accumulated conversation history included with a request:
  /// oldest turns are dropped first so follow-ups cannot outgrow the model's
  /// context window.
  static const historyCharacterBudget = 30000;

  /// Common words ignored when choosing which transcript lines best match a
  /// question in the abridged prompt.
  static const _stopwords = <String>{
    'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'any', 'can', 'her', 'was', 'one', 'our', 'out', 'day',
    'get', 'has', 'him', 'his', 'how', 'its', 'new', 'now', 'old', 'see', 'two', 'way', 'who', 'did', 'does', 'what',
    'when', 'where', 'which', 'this', 'that', 'with', 'they', 'them', 'there', 'their', 'from', 'have', 'about',
    'talk', 'talking', 'said', 'says', 'episode', 'podcast', 'please', 'tell', 'give', 'show', 'find', 'mention',
    'mentions', 'mentioning', 'discuss', 'discusses', 'discussed', 'covered', 'cover', 'time', 'timecode', 'timestamp',
    'were', 'will', 'would', 'could', 'should', 'into', 'than', 'then', 'also', 'just', 'like', 'some', 'more',
    'very', 'much', 'been', 'being', 'because', 'right',
  };

  final String endpoint;
  final String apiKey;
  final String model;
  final Dio dio;

  /// The in-flight request's cancellation token. Chat is single-flight (the
  /// bloc refuses asks while busy), so a single slot is sufficient.
  CancelToken? _activeCancelToken;
  bool _cancelRequested = false;

  OpenAiChatService({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    Dio? dio,
  }) : dio = dio ??
          Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(minutes: 2),
          ));

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
  }

  @override
  Stream<String> send(AiChatRequest request) async* {
    final url = endpoint.replaceAll(RegExp(r'/+$'), '');
    final completions = url.endsWith('/chat/completions') ? url : '$url/chat/completions';
    final cancelToken = CancelToken();

    _activeCancelToken = cancelToken;
    _cancelRequested = false;

    try {
      final response = await dio.post<ResponseBody>(
        completions,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
        ),
        data: jsonEncode({
          'model': model,
          'stream': true,
          'messages': buildMessages(request),
        }),
        cancelToken: cancelToken,
      );

      /// Decode the SSE stream through a UTF-8 decoder and line splitter so
      /// incomplete multibyte sequences and partial lines carry across chunk
      /// boundaries instead of being corrupted.
      final lines = response.data!.stream.cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());

      await for (final line in lines) {
        final text = parseSseData(line);

        if (text != null && text.isNotEmpty) {
          yield text;
        }
      }
    } catch (error) {
      /// An abort via [cancel] surfaces as a cancelled request after the
      /// listener is already gone; swallow it rather than surfacing an
      /// unhandled error. Genuine failures still propagate.
      if (_cancelRequested || (error is DioException && error.type == DioExceptionType.cancel)) {
        return;
      }

      rethrow;
    } finally {
      _activeCancelToken = null;
      _cancelRequested = false;
    }
  }

  /// Refuses to send the API key over a cleartext connection unless the host
  /// is local or on a private network (emulators and self-hosted servers).
  void _assertSecureEndpoint(String completions) {
    final uri = Uri.tryParse(completions);

    if (uri == null || uri.scheme != 'http') {
      return;
    }

    final host = uri.host;
    final private = host == 'localhost' || host == '127.0.0.1' || host.startsWith('10.') || host.startsWith('192.168.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host);

    if (!private) {
      throw AiChatException('Refusing to send the API key over an insecure connection. Use https:// or a local server.');
    }
  }

  /// Builds the chat messages for [request]: a system prompt with the layered
  /// transcript context, the prior conversation turns (bounded to the newest
  /// turns which fit the history budget) and the user's question.
  List<Map<String, String>> buildMessages(AiChatRequest request) {
    return <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt(request)},
      for (final message in boundedHistory(request.history))
        {'role': message.fromUser ? 'user' : 'assistant', 'content': message.text},
      {'role': 'user', 'content': request.question},
    ];
  }

  /// Trims [history] to the newest turns whose combined text fits
  /// [historyCharacterBudget]. The most recent turn is always kept, even if
  /// it alone exceeds the budget.
  @visibleForTesting
  List<AiChatMessage> boundedHistory(List<AiChatMessage> history) {
    var size = 0;
    var oldestKept = 0;

    for (var i = history.length - 1; i >= 0; i--) {
      size += history[i].text.length;

      if (size > historyCharacterBudget && i < history.length - 1) {
        oldestKept = i + 1;
        break;
      }
    }

    return history.sublist(oldestKept);
  }

  String _systemPrompt(AiChatRequest request) {
    final buffer = StringBuffer();

    buffer.write('You are a concise assistant answering questions about the podcast episode '
        '"${request.episodeTitle}". Answer from the transcript provided by default. '
        'When you use the transcript, cite positions as [mm:ss] (or [hh:mm:ss] for an hour or longer) '
        'copied from it so the listener can jump straight there; when quoting a passage you may cite '
        'a short range such as [0:45–0:57], which jumps to its start. '
        'If the question is not covered by the transcript, you may still answer it, '
        'but say briefly that the episode does not cover it.\n\n');

    final full = request.lines.map(_formatLine).join('\n');
    final position = request.currentPosition;

    buffer.write('CURRENT POSITION: [${_format(position)}]\n\n');

    if (full.length <= transcriptCharacterBudget) {
      buffer.write('TRANSCRIPT:\n$full');
    } else {
      /// The transcript is too large: provide the recent context window plus
      /// keyword matches for the question.
      final recent = request.recentLines.map(_formatLine).join('\n');
      final keywords = request.question
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((word) => word.length > 2)
          .toSet();

      /// Score each line by how many distinct keywords it hits, so the
      /// bounded section fills with the most relevant lines rather than
      /// everything containing a single common word.
      final scored = request.lines
          .map((line) {
            final text = (line.data ?? '').toLowerCase();
            final score = keywords.where(text.contains).length;

            return MapEntry(line, score);
          })
          .where((entry) => entry.value > 0)
          .toList();

      scored.sort((a, b) {
        final byScore = b.value.compareTo(a.value);

        if (byScore != 0) {
          return byScore;
        }

        return a.key.start.compareTo(b.key.start);
      });

      final matches = scored.map((entry) => entry.key).toList();

      buffer.write('TRANSCRIPT (abridged: recent context and keyword matches only):\n');
      buffer.write('RECENT CONTEXT:\n$recent\n\n');

      if (matches.isNotEmpty) {
        /// Bound the keyword section: a broad question can otherwise match
        /// most of the transcript and push the request over the model's
        /// context window, so stop once the section reaches its own budget.
        final bounded = <String>[];
        var size = 0;

        for (final match in matches) {
          final formatted = _formatLine(match);

          if (bounded.isNotEmpty && size + formatted.length > keywordMatchCharacterBudget) {
            break;
          }

          bounded.add(formatted);
          size += formatted.length;
        }

        buffer.write('KEYWORD MATCHES:\n${bounded.join('\n')}');
      }
    }

    return buffer.toString();
  }

  String _formatLine(dynamic line) {
    final start = line.start as Duration;
    final hh = start.inHours;
    final mm = start.inMinutes % 60;
    final ss = start.inSeconds % 60;
    final label = hh > 0 ? '$hh:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}' : '$mm:${ss.toString().padLeft(2, '0')}';
    final speaker = (line.speaker as String? ?? '').trim();
    final text = line.data as String? ?? '';

    return '[$label] ${speaker.isEmpty ? '' : '$speaker: '}$text';
  }

  String _format(Duration position) {
    final hh = position.inHours;
    final mm = position.inMinutes % 60;
    final ss = position.inSeconds % 60;

    return hh > 0 ? '$hh:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}' : '$mm:${ss.toString().padLeft(2, '0')}';
  }

  /// Extracts the content delta from a single SSE line, or null when the line
  /// carries no content (comments, keep alive pings and the [DONE] sentinel).
  static String? parseSseData(String line) {
    final trimmed = line.trim();

    if (!trimmed.startsWith('data:')) {
      return null;
    }

    final payload = trimmed.substring(5).trim();

    if (payload.isEmpty || payload == '[DONE]') {
      return null;
    }

    try {
      final json = jsonDecode(payload);

      if (json is! Map<String, dynamic>) {
        return null;
      }

      final error = json['error'];

      if (error != null) {
        throw AiChatException(error is Map ? (error['message']?.toString() ?? 'AI provider error') : 'AI provider error');
      }

      final choices = json['choices'];

      if (choices is List && choices.isNotEmpty) {
        final delta = choices.first['delta'];

        if (delta is Map<String, dynamic>) {
          final content = delta['content'];

          if (content is String) {
            return content;
          }
        }
      }
    } on AiChatException {
      rethrow;
    } catch (_) {
      /// Ignore malformed keep alive / partial lines.
      return null;
    }

    return null;
  }
}

/// Raised when the AI provider returns an error payload.
class AiChatException implements Exception {
  final String message;

  AiChatException(this.message);

  @override
  String toString() => message;
}
