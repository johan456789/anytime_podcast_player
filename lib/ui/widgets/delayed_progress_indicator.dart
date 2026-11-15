// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/ui/widgets/platform_progress_indicator.dart';
import 'package:flutter/material.dart';

/// This class returns a platform-specific spinning indicator after a time specified
/// in milliseconds.
///
/// Defaults to 1 second. This can be used as a place holder for cached images. By
/// delaying for several milliseconds it can reduce the occurrences of placeholders
/// flashing on screen as the cached image is loaded. Images that take longer to fetch
/// or process from the cache will result in a [PlatformProgressIndicator] indicator
/// being displayed.
class DelayedCircularProgressIndicator extends StatefulWidget {
  const DelayedCircularProgressIndicator({
    super.key,
  });

  @override
  State<DelayedCircularProgressIndicator> createState() => _DelayedCircularProgressIndicatorState();
}

class _DelayedCircularProgressIndicatorState extends State<DelayedCircularProgressIndicator> {
  static const delay = Duration(milliseconds: 1000);

  Timer? _timer;
  bool _elapsed = false;

  @override
  void initState() {
    super.initState();

    _timer = Timer(delay, () {
      if (mounted) {
        setState(() {
          _elapsed = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _elapsed
        ? const Center(
            child: PlatformProgressIndicator(),
          )
        : Container();
  }
}
