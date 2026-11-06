// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/core/timestamp_text.dart';
import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/services/ai/mock_ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

Subtitle _line(int index, Duration start, String text, {String speaker = ''}) {
  return Subtitle(
    index: index,
    start: start,
    end: start + const Duration(seconds: 4),
    data: text,
    speaker: speaker,
  );
}

AiChatRequest _request(String question, List<Subtitle> lines, {Duration position = Duration.zero}) {
  return AiChatRequest(
    question: question,
    episodeTitle: 'Test Episode',
    currentPosition: position,
    lines: lines,
    recentLines: lines,
  );
}

void main() {
  late MockAiChatService service;

  final transcript = <Subtitle>[
    _line(0, const Duration(minutes: 0), 'Welcome to the show, today we are talking about space telescopes.',
        speaker: 'Host'),
    _line(1, const Duration(minutes: 2), 'The mirror is made of beryllium and coated with gold.', speaker: 'Guest'),
    _line(2, const Duration(minutes: 10), 'Launching the telescope was the riskiest part of the mission.',
        speaker: 'Guest'),
    _line(3, const Duration(minutes: 20), 'Funding for the mission nearly got cancelled in 2011.', speaker: 'Host'),
    _line(4, const Duration(minutes: 40), 'The first images revealed galaxies from the early universe.',
        speaker: 'Guest'),
    _line(5, const Duration(minutes: 50), 'Next we look at what comes after for astronomy.', speaker: 'Host'),
  ];

  setUp(() {
    service = MockAiChatService(chunkDelay: Duration.zero);
  });

  group('MockAiChatService', () {
    test('streams the reply in multiple chunks', () async {
      final chunks = <String>[];

      await for (final chunk in service.send(_request('summarize this episode', transcript))) {
        chunks.add(chunk);
      }

      expect(chunks.length, greaterThan(3));
      expect(chunks.join(), contains('Test Episode'));
    });

    test('summary answer contains timestamps', () async {
      final reply = await service.send(_request('Can you summarize this episode?', transcript)).join();

      expect(reply, contains('summary'));
      expect(containsTimestamp(reply), isTrue);
    });

    test('topics answer lists timestamped segments', () async {
      final reply = await service.send(_request('What topics are covered?', transcript)).join();

      expect(containsTimestamp(reply), isTrue);
    });

    test('keyword question cites the line where the keyword is spoken', () async {
      final reply = await service.send(_request('When do they talk about beryllium?', transcript)).join();

      expect(reply, contains('2:00'));
      expect(reply, contains('beryllium'));
    });

    test('multiple keyword matches cite more than one timecode', () async {
      final lines = <Subtitle>[
        _line(0, const Duration(minutes: 1), 'The rover landed on Mars in February.'),
        _line(1, const Duration(minutes: 15), 'Mars samples return is the next goal.'),
        _line(2, const Duration(minutes: 30), 'Weather on Mars is harsh.'),
      ];

      final reply = await service.send(_request('When is Mars mentioned?', lines)).join();

      expect(containsTimestamp(reply), isTrue);
      expect('1:00', isNot(equals('15:00')));
      expect(reply, contains('1:00'));
      expect(reply, contains('15:00'));
      expect(reply, contains('30:00'));
    });

    test('unknown topic returns a polite fallback', () async {
      final reply = await service.send(_request('What about quantum blockchain synergies?', transcript)).join();

      expect(reply, contains("couldn't find"));
    });

    test('question about current position quotes the nearby line', () async {
      final reply = await service.send(
        _request('What are they talking about right now?', transcript, position: const Duration(minutes: 41)),
      ).join();

      expect(reply, contains('40:00'));
      expect(reply, contains('galaxies'));
    });

    test('empty transcript explains that there is no transcript', () async {
      final reply = await service.send(_request('Summarize this', <Subtitle>[])).join();

      expect(reply.toLowerCase(), contains('no transcript'));
    });
  });
}
