// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/ai_chat.dart';

/// Provides AI chat about the currently playing episode.
///
/// Implementations stream the reply in chunks so the UI can render it as it
/// arrives. Replies should cite transcript positions using `[mm:ss]` or
/// `[hh:mm:ss]` timestamps; the UI renders these as tappable chips which seek
/// playback to that position.
abstract class AiChatService {
  /// Sends the user's [request] and streams the assistant's reply in chunks.
  ///
  /// The returned stream is single-subscription; cancelling the subscription
  /// stops delivery but does not abort the underlying request — call [cancel]
  /// for that.
  Stream<String> send(AiChatRequest request);

  /// Aborts any in-flight request so the provider stops generating. The
  /// default implementation does nothing for services without cancellable
  /// requests.
  Future<void> cancel() async {}
}
