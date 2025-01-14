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
  ScrollController? _scrollController;
  bool _showMiniPlayer = false;
  
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController?.removeListener(_onScroll);
    _scrollController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController?.hasClients ?? false) {
      final showMini = _scrollController!.offset > 200;
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
      page: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
      page: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(height: 8),
            QueueDisplay(),
          ],
        ),
      ),
    ),
    PageData(
      title: 'LYRICS',
      icon: Icons.lyrics_rounded,
      page: const LyricsWidget(),
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
            NestedScrollView(
              controller: _scrollController,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _showMiniPlayer ? 0.0 : 1.0,
                    child: Column(
                      children: const [
                        Player(isLargeScreen: false),
                        SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyTabDelegate(
                    child: SimplePageIndicator(
                      pages: _pages,
                      pageController: _pageController,
                    ),
                  ),
                ),
              ],
              body: PageView(
                controller: _pageController,
                children: _pages.map((page) => page.page).toList(),
              ),
            ),
            if (_showMiniPlayer)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Player(
                  isLargeScreen: false,
                  isMiniPlayer: true,
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
    }
  }
}

class _StickyTabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyTabDelegate({
    required this.child,
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
  double get maxExtent => 56.0;

  @override
  double get minExtent => 56.0;

  @override
  bool shouldRebuild(covariant _StickyTabDelegate oldDelegate) => false;
}