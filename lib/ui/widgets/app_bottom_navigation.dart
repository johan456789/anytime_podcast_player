// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/ui/pager_bloc.dart';
import 'package:anytime/l10n/L.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The app's bottom navigation bar offering the Library, Discover and
/// Downloads destinations.
///
/// Set [embedded] to true when the bar is rendered on top of another route,
/// such as on the podcast details screen. An embedded bar switches the page
/// underneath and then closes any routes above the home route so the user
/// always lands on the tab they selected.
class AppBottomNavigationBar extends StatelessWidget {
  final bool embedded;

  const AppBottomNavigationBar({
    super.key,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pager = Provider.of<PagerBloc>(context);

    return StreamBuilder<int>(
        stream: pager.currentPage,
        initialData: 0,
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          int index = snapshot.data ?? 0;

          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: theme.bottomAppBarTheme.color,
            selectedIconTheme: theme.iconTheme,
            selectedItemColor: theme.iconTheme.color,
            selectedFontSize: 11.0,
            unselectedFontSize: 11.0,
            unselectedItemColor: HSLColor.fromColor(theme.bottomAppBarTheme.color!).withLightness(0.8).toColor(),
            currentIndex: index,
            onTap: (int selected) {
              pager.changePage(selected);

              if (embedded) {
                /// Reveal the newly selected tab by closing any routes above
                /// the home route (podcast details, search, settings, ...).
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: index == 0 ? const Icon(Icons.library_music) : const Icon(Icons.library_music_outlined),
                label: L.of(context)!.library,
              ),
              // To be fleshed out later.
              // BottomNavigationBarItem(
              //   icon: index == 0 ? Icon(Icons.article_rounded) : Icon(Icons.article_outlined),
              //   label: 'Episodes',
              // ),
              BottomNavigationBarItem(
                icon: index == 1 ? const Icon(Icons.explore) : const Icon(Icons.explore_outlined),
                label: L.of(context)!.discover,
              ),
              BottomNavigationBarItem(
                icon: index == 2 ? const Icon(Icons.download) : const Icon(Icons.download_outlined),
                label: L.of(context)!.downloads,
              ),
            ],
          );
        });
  }
}
