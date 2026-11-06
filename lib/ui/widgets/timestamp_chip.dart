// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

/// A tappable timestamp reference within an AI chat reply which seeks
/// playback. [label] is displayed as-is (e.g. `0:45` or `0:45–0:57`); a range
/// seeks to [seconds], the start of the range.
class TimestampChip extends StatelessWidget {
  final String label;
  final int seconds;
  final void Function(int seconds) onSeek;

  const TimestampChip({
    super.key,
    required this.label,
    required this.seconds,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        onTap: () => onSeek(seconds),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.secondary, width: 1.0),
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
