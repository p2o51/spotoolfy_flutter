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
  late final PageController _pageController;

  bool _isExpanded = false;
  int _currentPageIndex = 2; // 默认显示 LYRICS 页面
  
  @override
  void initState() {
    super.initState();
    
    // Initialize PageController with the correct starting page
    _pageController = PageController(initialPage: _currentPageIndex); 
    
    // 监听页面变化
    _pageController.addListener(_onPageChanged);
    
    // No longer need jumpToPage here as initialPage is set
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (_pageController.hasClients) { // Check if controller is attached
    //      _pageController.jumpToPage(_currentPageIndex);
    //    }
    // });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    final currentPage = _pageController.hasClients ? (_pageController.page?.round() ?? _currentPageIndex) : _currentPageIndex;
    
    setState(() {
      _isExpanded = !_isExpanded;
    });
    
    // 确保页面切换后保持在当前页面
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(currentPage);
      }
    });
  }

  void _onPageChanged() {
    if (_pageController.hasClients && _pageController.page != null) {
      final newPage = _pageController.page!.round();
      if (newPage != _currentPageIndex) {
        setState(() {
          _currentPageIndex = newPage;
        });
      }
    }
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
      title: 'QUEUE',
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
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Centered indicator
          SimplePageIndicator(
            pages: _pages,
            pageController: _pageController,
          ),
          // Button only on small screens, positioned at the end
          if (!isLargeScreen)
            Positioned(
              right: 0,
              child: IconButton(
                icon: Icon(_isExpanded ? Icons.expand_more : Icons.expand_less),
                onPressed: _toggleExpand,
                tooltip: _isExpanded ? 'Collapse' : 'Expand',
              ),
            ),
        ],
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
                    onPageChanged: (index) {
                      setState(() {
                        _currentPageIndex = index;
                      });
                    },
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    if (isLargeScreen) {
      // On large screens, always use the side-by-side layout
      return _buildCollapsedLargeLayout();
    } else {
      // On small screens, maintain a single PageView while animating other parts
      return Scaffold(
        body: Column(
          children: [
            // Only animate this top part
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0.0, 0.1),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: _isExpanded
                ? KeyedSubtree(
                    key: const ValueKey('expanded_header'),
                    child: const Player(isLargeScreen: false, isMiniPlayer: true),
                  )
                : KeyedSubtree(
                    key: const ValueKey('collapsed_header'),
                    child: Column(
                      children: const [
                        Player(isLargeScreen: false),
                        SizedBox(height: 16),
                      ],
                    ),
                  ),
            ),
            // Tab header stays consistent
            _buildTabHeader(),
            // PageView stays consistent across states
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPageIndex = index;
                  });
                },
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
  }
}