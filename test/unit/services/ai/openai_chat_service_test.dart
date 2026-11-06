// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';
import 'package:anytime/services/ai/mock_ai_chat_service.dart';
import 'package:anytime/services/ai/openai_chat_service.dart';
import 'package:anytime/services/ai/settings_ai_chat_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mocks/mock_settings_service.dart';

/// Serves canned SSE bytes for any request and records the request body.
class FakeSseAdapter implements HttpClientAdapter {
  final List<List<int>> chunks;
  String? lastRequestBody;

  FakeSseAdapter.fromEvents(List<String> events)
      : chunks = [for (final event in events) Uint8List.fromList(utf8.encode(event))];

  FakeSseAdapter.raw(this.chunks);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequestBody = await requestStream?.cast<List<int>>().transform(utf8.decoder).join();

    final controller = StreamController<Uint8List>();

    for (final chunk in chunks) {
      controller.add(Uint8List.fromList(chunk));
    }

    unawaited(controller.close());

    return ResponseBody(controller.stream, 200);
  }

  @override
  void close({bool force = false}) {}
}

/// A request which never completes its response headers until the caller's
/// cancel token is fired, simulating a provider still generating.
class FakePendingAdapter implements HttpClientAdapter {
  bool sawCancellation = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final completer = Completer<void>();

    options.cancelToken?.whenCancel.then((_) {
      sawCancellation = true;

      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;

    return ResponseBody(const Stream.empty(), 200);
  }

  @override
  void close({bool force = false}) {}
}

/// Counts cancel() calls so the settings wrapper's forwarding can be tested.
class _CountingCancelService extends AiChatService {
  int cancelCount = 0;

  @override
  Stream<String> send(AiChatRequest request) async* {
    yield 'reply';
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}

/// Wrapper under test with a spy delegate so cancellation forwarding can be
/// observed.
class _SpyWrapper extends SettingsAiChatService {
  _SpyWrapper(super.settingsService);

  final _CountingCancelService delegate = _CountingCancelService();

  @override
  AiChatService createProviderService() => delegate;
}

AiChatRequest _request({Duration position = const Duration(minutes: 2)}) {
  return AiChatRequest(
    question: 'When are tickets on sale?',
    episodeTitle: 'Test Episode',
    currentPosition: position,
    lines: <Subtitle>[
      Subtitle(index: 0, start: const Duration(minutes: 1), end: const Duration(minutes: 1, seconds: 4), data: 'Hello world'),
      Subtitle(
          index: 1,
          start: const Duration(minutes: 2, seconds: 7),
          end: const Duration(minutes: 2, seconds: 11),
          data: 'Tickets go on sale',
          speaker: 'Host'),
    ],
    recentLines: const <Subtitle>[],
  );
}

void main() {
  group('OpenAiChatService.parseSseData', () {
    test('extracts content deltas', () {
      expect(
        OpenAiChatService.parseSseData('data: {"choices":[{"delta":{"content":"Hi"}}]}'),
        'Hi',
      );
    });

    test('returns null for [DONE], comments and empty lines', () {
      expect(OpenAiChatService.parseSseData('data: [DONE]'), isNull);
      expect(OpenAiChatService.parseSseData(': keep-alive'), isNull);
      expect(OpenAiChatService.parseSseData('data: '), isNull);
      expect(OpenAiChatService.parseSseData(''), isNull);
    });

    test('returns null for deltas without content', () {
      expect(OpenAiChatService.parseSseData('data: {"choices":[{"delta":{}}]}'), isNull);
    });

    test('throws AiChatException for provider error payloads', () {
      expect(
        () => OpenAiChatService.parseSseData('data: {"error":{"message":"bad key"}}'),
        throwsA(isA<AiChatException>()),
      );
    });
  });

  group('OpenAiChatService.send', () {
    test('streams content deltas from an SSE response', () async {
      final adapter = FakeSseAdapter.fromEvents(<String>[
        'data: {"choices":[{"delta":{"content":"Found at "}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"[2:07]"}}]}\n\n',
        'data: [DONE]\n\n',
      ]);

      final service = OpenAiChatService(
        endpoint: 'http://localhost:9999/v1',
        apiKey: 'sk-test',
        model: 'test-model',
        dio: Dio()..httpClientAdapter = adapter,
      );

      final reply = await service.send(_request()).join();

      expect(reply, 'Found at [2:07]');

      final body = jsonDecode(adapter.lastRequestBody!);
      expect(body['model'], 'test-model');
      expect(body['stream'], isTrue);
    });

    test('preserves multibyte characters split across network chunks', () async {
      /// The word 'dará' is split mid-character: 'á' is 0xC3 0xA1 and the
      /// network delivers only its first byte with the first chunk.
      const eventPrefix = 'data: {"choices":[{"delta":{"content":"dar';
      const eventSuffix = 'n"}}]}\n\n';

      final adapter = FakeSseAdapter.raw(<List<int>>[
        [...utf8.encode(eventPrefix), 0xC3],
        [0xA1, ...utf8.encode(eventSuffix)],
        utf8.encode('data: [DONE]\n\n'),
      ]);

      final service = OpenAiChatService(
        endpoint: 'http://localhost:9999/v1',
        apiKey: 'sk-test',
        model: 'test-model',
        dio: Dio()..httpClientAdapter = adapter,
      );

      final reply = await service.send(_request()).join();

      expect(reply, 'darán');
      expect(reply.contains(String.fromCharCode(0xFFFD)), isFalse);
    });

    test('builds a system prompt with the position and timestamped transcript', () {
      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');
      final messages = service.buildMessages(_request());

      final system = messages.first['content']!;
      expect(messages.first['role'], 'system');
      expect(system, contains('CURRENT POSITION: [2:00]'));
      expect(system, contains('[1:00] Hello world'));
      expect(system, contains('[2:07] Host: Tickets go on sale'));
      expect(messages.last['content'], 'When are tickets on sale?');
    });

    test('bounds keyword matches when the transcript exceeds the budget', () {
      /// 200 lines of ~800 chars each (~160k chars total) all containing the
      /// broad keyword 'the': well over the full-transcript budget.
      final filler = 'the ' * 200;
      final lines = <Subtitle>[
        for (var i = 0; i < 200; i++)
          Subtitle(
            index: i,
            start: Duration(minutes: i),
            end: Duration(minutes: i, seconds: 30),
            data: 'Line $i about $filler',
          ),
      ];

      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');
      final messages = service.buildMessages(AiChatRequest(
        question: 'What about the thing?',
        episodeTitle: 'Test Episode',
        currentPosition: const Duration(minutes: 2),
        lines: lines,
        recentLines: const <Subtitle>[],
      ));

      final system = messages.first['content']!;

      expect(system, contains('CURRENT POSITION: [2:00]'));
      expect(system, contains('TRANSCRIPT (abridged'));

      /// The keyword section must be bounded rather than re-serialising the
      /// entire oversized transcript.
      final keywordSection = system.split('KEYWORD MATCHES:').last;
      final keywordLines = keywordSection.split('\n').where((line) => line.startsWith('[')).length;

      expect(keywordLines, lessThan(200));
      expect(keywordSection.length, lessThanOrEqualTo(OpenAiChatService.keywordMatchCharacterBudget + 2000));

      /// Matches after the current playback position (2 minutes) must still
      /// be included: the listener can ask about a passage they have not
      /// reached yet.
      expect(keywordSection, contains('[3:00]'));
    });

    test('cancel aborts the pending provider request', () async {
      final adapter = FakePendingAdapter();
      final service = OpenAiChatService(
        endpoint: 'http://localhost:9999/v1',
        apiKey: 'sk-test',
        model: 'test-model',
        dio: Dio()..httpClientAdapter = adapter,
      );

      final chunks = <String>[];
      final done = Completer<void>();
      final subscription = service.send(_request()).listen(
            chunks.add,
            onError: done.completeError,
            onDone: done.complete,
          );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(chunks, isEmpty);

      await service.cancel();
      await done.future.timeout(const Duration(seconds: 2));

      expect(adapter.sawCancellation, isTrue);
      expect(chunks, isEmpty);

      await subscription.cancel();
    });

    test('forwards cancellation to the active provider delegate', () async {
      final mock = MockSettingsService()
        ..aiChatApiKey = 'sk-test'
        ..aiChatEndpoint = 'http://localhost:9999/v1';
      final wrapper = SettingsAiChatService(mock);

      final wrapperWithSpy = _SpyWrapper(mock);

      await wrapperWithSpy.send(_request()).drain();

      expect(wrapperWithSpy.delegate.cancelCount, 0);

      await wrapperWithSpy.cancel();

      expect(wrapperWithSpy.delegate.cancelCount, 1);
    });

    test('includes prior conversation turns before the current question', () {
      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');
      final request = AiChatRequest(
        question: 'Where did they say that?',
        episodeTitle: 'Test Episode',
        currentPosition: Duration.zero,
        lines: const <Subtitle>[],
        recentLines: const <Subtitle>[],
        history: const <AiChatMessage>[
          AiChatMessage(fromUser: true, text: 'What about darán?'),
          AiChatMessage(fromUser: false, text: 'It means they will give.'),
        ],
      );

      final messages = service.buildMessages(request);

      expect(messages, hasLength(4));
      expect(messages[0]['role'], 'system');
      expect(messages[1], {'role': 'user', 'content': 'What about darán?'});
      expect(messages[2], {'role': 'assistant', 'content': 'It means they will give.'});
      expect(messages[3], {'role': 'user', 'content': 'Where did they say that?'});
    });

    test('bounds the conversation history to the newest turns within budget', () {
      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');

      /// 40 turns of ~1000 chars each (~40k chars total) exceed the 30k
      /// history budget, so only the newest turns may be kept.
      final history = <AiChatMessage>[
        for (var i = 0; i < 40; i++)
          AiChatMessage(fromUser: i.isEven, text: 'turn $i ${'x' * 1000}'),
      ];

      final bounded = service.boundedHistory(history);

      expect(bounded.length, lessThan(history.length));
      expect(bounded.length, greaterThanOrEqualTo(1));
      expect(bounded.first.text, contains('turn'));
      expect(bounded.last.text, contains('turn 39'));

      final total = bounded.fold<int>(0, (sum, message) => sum + message.text.length);
      expect(total + 1000, greaterThan(OpenAiChatService.historyCharacterBudget));
      expect(total, lessThanOrEqualTo(OpenAiChatService.historyCharacterBudget + 1000));
    });

    test('always keeps the most recent turn even if it alone exceeds the budget', () {
      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');

      final history = <AiChatMessage>[
        const AiChatMessage(fromUser: true, text: 'older turn'),
        AiChatMessage(fromUser: false, text: 'x' * 40000),
      ];

      final bounded = service.boundedHistory(history);

      expect(bounded, hasLength(1));
      expect(bounded.first, same(history.last));
    });

    test('keeps the full history when it fits the budget', () {
      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');

      final history = <AiChatMessage>[
        const AiChatMessage(fromUser: true, text: 'question one'),
        const AiChatMessage(fromUser: false, text: 'answer one'),
      ];

      final bounded = service.boundedHistory(history);

      expect(bounded, hasLength(2));
      expect(bounded[0].text, 'question one');
      expect(bounded[1].text, 'answer one');
    });

    test('omits bounded-out older turns from the provider messages', () {
      final service = OpenAiChatService(endpoint: 'http://x/v1', apiKey: 'k', model: 'm');

      final history = <AiChatMessage>[
        const AiChatMessage(fromUser: true, text: 'oldest question'),
        AiChatMessage(fromUser: false, text: 'x' * 40000),
        const AiChatMessage(fromUser: true, text: 'newest question'),
      ];

      final messages = service.buildMessages(AiChatRequest(
        question: 'and now?',
        episodeTitle: 'Test Episode',
        currentPosition: Duration.zero,
        lines: const <Subtitle>[],
        recentLines: const <Subtitle>[],
        history: history,
      ));

      final contents = messages.map((message) => message['content']).toList();
      expect(contents, contains('newest question'));
      expect(contents, isNot(contains('oldest question')));
    });
  });

  group('SettingsAiChatService', () {
    test('reports unconfigured without an API key', () {
      final service = SettingsAiChatService(MockSettingsService());

      expect(service.isConfigured, isFalse);
    });

    test('reports configured once endpoint and key are set', () {
      final mock = MockSettingsService()..aiChatApiKey = 'sk-test';
      final service = SettingsAiChatService(mock);

      expect(service.isConfigured, isTrue);
    });

    test('falls back to the demo service when unconfigured', () async {
      final service = SettingsAiChatService(MockSettingsService());

      final reply = await service.send(_request()).join();

      expect(reply, isNotEmpty);
      expect(reply, isNot(equals('Found at [2:07]')));
      expect(service.send(_request()), isA<Stream<String>>());
    });

    test('demo fallback streams a transcript grounded reply', () async {
      final service = MockAiChatService(chunkDelay: Duration.zero);

      final reply = await service.send(_request()).join();

      expect(reply, contains('2:07'));
    });
  });
}
