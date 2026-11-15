// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'package:anytime/entities/episode.dart';
import 'package:flutter/foundation.dart';

/// Holds the episode selection for the podcast details page.
///
/// Episodes are keyed by [Episode.guid] - an [Episode]'s equality includes
/// mutable playback state, so keying on the GUID keeps the selection stable
/// while bulk actions mutate the episodes. Selected episodes are kept in
/// selection order so bulk queue additions are queued in the order the user
/// picked them.
class EpisodeSelection extends ChangeNotifier {
  final LinkedHashMap<String, Episode> _selected = LinkedHashMap<String, Episode>();
  bool _selecting = false;

  /// True while the user is in selection mode, even if nothing is selected.
  bool get selecting => _selecting;

  /// The number of currently selected episodes.
  int get count => _selected.length;

  /// The selected episodes in selection order.
  List<Episode> get episodes => List<Episode>.unmodifiable(_selected.values);

  /// True if the given episode is selected.
  bool isSelected(Episode episode) => _selected.containsKey(episode.guid);

  /// True if every episode in [episodes] is selected.
  bool containsAll(Iterable<Episode> episodes) => episodes.every((e) => _selected.containsKey(e.guid));

  /// Enters selection mode with [episode] selected. Typically triggered by a
  /// long-press on an episode tile.
  void enterSelectionWith(Episode episode) {
    _selecting = true;
    _selected
      ..clear()
      ..[episode.guid] = episode;

    notifyListeners();
  }

  void toggle(Episode episode) {
    if (_selected.remove(episode.guid) == null) {
      _selected[episode.guid] = episode;
    }

    notifyListeners();
  }

  /// Enters selection mode and selects every episode in [episodes], replacing
  /// the current selection.
  void selectAll(Iterable<Episode> episodes) {
    _selecting = true;
    _selected.clear();

    for (var e in episodes) {
      _selected[e.guid] = e;
    }

    notifyListeners();
  }

  /// Clears the selection but stays in selection mode.
  void selectNone() {
    _selected.clear();

    notifyListeners();
  }

  /// Leaves selection mode and clears the selection.
  void clear() {
    _selecting = false;
    _selected.clear();

    notifyListeners();
  }
}
