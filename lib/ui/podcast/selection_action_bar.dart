// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/ui/podcast/episode_selection.dart';
import 'package:flutter/material.dart';

/// The bulk action bar shown at the bottom of the podcast details page while
/// the user is selecting episodes.
///
/// The bar offers the same actions as an individual episode tile, applied to
/// every selected episode. Actions which do not apply to the current
/// selection (e.g. downloading when every selected episode is already
/// downloaded) are disabled rather than hidden to keep the bar stable.
class SelectionActionBar extends StatelessWidget {
  final EpisodeSelection selection;

  final VoidCallback onMarkPlayed;
  final VoidCallback onMarkUnplayed;
  final VoidCallback onDownload;
  final VoidCallback onQueue;
  final VoidCallback onDeleteDownloads;

  const SelectionActionBar({
    super.key,
    required this.selection,
    required this.onMarkPlayed,
    required this.onMarkUnplayed,
    required this.onDownload,
    required this.onQueue,
    required this.onDeleteDownloads,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episodes = selection.episodes;
    final hasDownloads = episodes.any((e) => e.downloaded);
    final hasDownloadable = episodes.any((e) => e.downloadState == DownloadState.none && !e.downloaded);

    return Material(
      color: theme.bottomAppBarTheme.color,
      elevation: 8.0,
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SelectionActionButton(
              icon: Icons.check_circle_outline,
              semanticLabel: L.of(context)!.mark_played_label,
              label: L.of(context)!.bulk_played_label,
              onPressed: episodes.isNotEmpty ? onMarkPlayed : null,
            ),
            _SelectionActionButton(
              icon: Icons.unpublished_outlined,
              semanticLabel: L.of(context)!.mark_unplayed_label,
              label: L.of(context)!.bulk_unplayed_label,
              onPressed: episodes.isNotEmpty ? onMarkUnplayed : null,
            ),
            _SelectionActionButton(
              icon: Icons.playlist_add_outlined,
              semanticLabel: L.of(context)!.semantics_add_to_queue,
              label: L.of(context)!.bulk_queue_label,
              onPressed: episodes.isNotEmpty ? onQueue : null,
            ),
            _SelectionActionButton(
              icon: Icons.save_alt,
              semanticLabel: L.of(context)!.download_episode_button_label,
              label: L.of(context)!.bulk_download_label,
              onPressed: hasDownloadable ? onDownload : null,
            ),
            _SelectionActionButton(
              icon: Icons.delete_outline,
              semanticLabel: L.of(context)!.delete_episode_button_label,
              label: L.of(context)!.bulk_delete_downloads_label,
              onPressed: hasDownloads ? onDeleteDownloads : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// An icon and label pair in the style of the expanded episode tile's action
/// buttons.
class _SelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final String label;
  final VoidCallback? onPressed;

  const _SelectionActionButton({
    required this.icon,
    required this.semanticLabel,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final color = enabled ? theme.iconTheme.color : theme.disabledColor;

    return Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0.0)),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              semanticLabel: semanticLabel,
              size: 22,
              color: color,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2.0),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: color,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
