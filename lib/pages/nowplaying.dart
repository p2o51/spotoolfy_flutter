//nowplaying.dart
import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/player.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import 'package:spotoolfy_flutter/widgets/add_note.dart';
import 'package:spotoolfy_flutter/widgets/queue.dart';
import 'package:spotoolfy_flutter/widgets/lyrics.dart';
import 'package:spotoolfy_flutter/widgets/mdtab.dart';

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> with AutomaticKeepAliveClientMixin {
  final PageController _pageController = PageController(initialPage: 2);
  final ScrollController _scrollController = ScrollController();
  bool _showMiniPlayer = false;
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final showMini = _scrollController.offset > 200;
      if (showMini != _showMiniPlayer) {
        setState(() {
          _showMiniPlayer = showMini;
        });
      }
    }
  }

  final List<PageData> _pages = [
    PageData(
      title: 'RECORDS',
      icon: Icons.comment_rounded,
      page: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Ratings(
              initialRating: 'good',
              onRatingChanged: (rating) {
                // Handle rating change if needed
              },
            ),
            const SizedBox(height: 16),
            const NotesDisplay(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    ),
    PageData(
      title: 'NOW PLAYING',
      icon: Icons.queue_music_rounded,
      page: const SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 8),
            QueueDisplay(),
          ],
        ),
      ),
    ),
    PageData(
      title: 'LYRICS',
      icon: Icons.lyrics_rounded,
      page: Column(
        children: [
          Expanded(child: LyricsWidget()),
        ],
      ),
    ),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    if (isLargeScreen) {
      return Scaffold(
        body: Row(
          children: [
            const Expanded(
              flex: 1,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Player(isLargeScreen: true),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  SimplePageIndicator(
                    pages: _pages,
                    pageController: _pageController,
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      children: _pages.map((page) => page.page).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (context) => const AddNoteSheet(),
            );
          },
          child: const Icon(Icons.add),
        ),
      );
    } else {
      return Scaffold(
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const Player(isLargeScreen: false),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyTabDelegate(
                    showMiniPlayer: _showMiniPlayer,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showMiniPlayer)
                          const Player(
                            isLargeScreen: false,
                            isMiniPlayer: true,
                          ),
                        SimplePageIndicator(
                          pages: _pages,
                          pageController: _pageController,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverFillRemaining(
                  child: PageView(
                    controller: _pageController,
                    children: _pages.map((page) => page.page).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (context) => const AddNoteSheet(),
            );
          },
          child: const Icon(Icons.add),
        ),
        floatingActionButtonLocation: _showMiniPlayer 
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.endFloat,
      );
    }
  }
}

class _StickyTabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final bool showMiniPlayer;

  _StickyTabDelegate({
    required this.child,
    required this.showMiniPlayer,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: maxExtent,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  double get maxExtent => showMiniPlayer ? 72.0 + 56.0 : 56.0;

  @override
  double get minExtent => showMiniPlayer ? 72.0 + 56.0 : 56.0;

  @override
  bool shouldRebuild(covariant _StickyTabDelegate oldDelegate) => 
    oldDelegate.showMiniPlayer != showMiniPlayer;
}