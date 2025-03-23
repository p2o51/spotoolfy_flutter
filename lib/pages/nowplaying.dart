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
  bool _isExpanded = false;
  
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

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  final List<PageData> _pages = [
    PageData(
      title: 'RECORDS',
      icon: Icons.comment_rounded,
      page: SingleChildScrollView(
        child: ConstrainedBox(
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
    ),
    PageData(
      title: 'NOW PLAYING',
      icon: Icons.queue_music_rounded,
      page: SingleChildScrollView(
        child: ConstrainedBox(
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
    ),
    PageData(
      title: 'LYRICS',
      icon: Icons.lyrics_rounded,
      page: const LyricsWidget(),
    ),
  ];

  @override
  bool get wantKeepAlive => true;

  Widget _buildTabHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          Expanded(
            child: SimplePageIndicator(
              pages: _pages,
              pageController: _pageController,
            ),
          ),
          IconButton(
            icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
            onPressed: _toggleExpand,
            tooltip: _isExpanded ? '收起' : '展开',
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedLayout(bool isLargeScreen) {
    return Scaffold(
      body: Column(
        children: [
          Player(isLargeScreen: isLargeScreen, isMiniPlayer: true),
          _buildTabHeader(),
          Expanded(
            child: PageView(
              controller: _pageController,
              children: _pages.map((page) => page.page).toList(),
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

  Widget _buildCollapsedLargeLayout() {
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
                _buildTabHeader(),
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
  }

  Widget _buildCollapsedSmallLayout() {
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
                    children: [
                      const Player(isLargeScreen: false),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabDelegate(
                  showMiniPlayer: _showMiniPlayer,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  child: _buildTabHeader(),
                ),
              ),
            ],
            body: PageView(
              controller: _pageController,
              children: _pages.map((page) => page.page).toList(),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _showMiniPlayer ? 1.0 : 0.0,
              child: const Player(
                isLargeScreen: false,
                isMiniPlayer: true,
              ),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    if (_isExpanded) {
      return _buildExpandedLayout(isLargeScreen);
    } else {
      return isLargeScreen 
          ? _buildCollapsedLargeLayout() 
          : _buildCollapsedSmallLayout();
    }
  }
}

class _StickyTabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final bool showMiniPlayer;
  final Color backgroundColor;

  _StickyTabDelegate({
    required this.child,
    required this.showMiniPlayer,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      padding: EdgeInsets.only(top: showMiniPlayer ? 64.0 : 0),
      height: maxExtent,
      color: backgroundColor,
      child: child,
    );
  }

  @override
  double get maxExtent => showMiniPlayer ? 120.0 : 56.0;

  @override
  double get minExtent => showMiniPlayer ? 120.0 : 56.0;

  @override
  bool shouldRebuild(covariant _StickyTabDelegate oldDelegate) {
    return oldDelegate.showMiniPlayer != showMiniPlayer ||
           oldDelegate.backgroundColor != backgroundColor;
  }
}