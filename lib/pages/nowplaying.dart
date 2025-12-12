//nowplaying.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotoolfy_flutter/utils/responsive.dart';
import 'package:spotoolfy_flutter/widgets/player.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/add_note.dart';
import 'package:spotoolfy_flutter/widgets/queue.dart';
import 'package:spotoolfy_flutter/widgets/lyrics.dart';
import 'package:spotoolfy_flutter/widgets/mdtab.dart';
import '../l10n/app_localizations.dart';

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> with AutomaticKeepAliveClientMixin {
  late final PageController _pageController;

  bool _isExpanded = false;
  int _currentPageIndex = 2; // 默认显示 LYRICS 页面
  
  // 缓存变量
  List<PageData>? _cachedPages;
  bool? _cachedIsLargeScreen;
  Size? _cachedScreenSize;
  
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
    HapticFeedback.lightImpact();
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

  // 优化的页面变化处理，减少不必要的setState调用
  void _onPageChangedOptimized(int index) {
    if (index != _currentPageIndex) {
      setState(() {
        _currentPageIndex = index;
      });
    }
  }

  List<PageData> _buildPages(BuildContext context) {
    // 使用缓存避免重复构建
    if (_cachedPages != null) {
      return _cachedPages!;
    }
    
    _cachedPages = [
      PageData(
        title: AppLocalizations.of(context)!.recordsTab,
        icon: Icons.comment_rounded,
        page: RepaintBoundary(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 0),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 8),
                  NotesDisplay(),
                  SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
      PageData(
        title: AppLocalizations.of(context)!.queueTab,
        icon: Icons.queue_music_rounded,
        page: RepaintBoundary(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 0),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 8),
                  QueueDisplay(),
                ],
              ),
            ),
          ),
        ),
      ),
      PageData(
        title: AppLocalizations.of(context)!.lyricsTab,
        icon: Icons.lyrics_rounded,
        page: const RepaintBoundary(
          child: LyricsWidget(),
        ),
      ),
    ];
    
    return _cachedPages!;
  }

  @override
  bool get wantKeepAlive => true;

  // 缓存屏幕尺寸信息
  bool _getIsLargeScreen(BuildContext context) {
    final currentSize = MediaQuery.of(context).size;

    // 如果尺寸发生变化，清除缓存
    if (_cachedScreenSize != currentSize) {
      _cachedScreenSize = currentSize;
      _cachedIsLargeScreen = null;
      _cachedPages = null; // 屏幕尺寸变化时也清除页面缓存
    }

    _cachedIsLargeScreen ??= currentSize.width >= Breakpoints.tablet;
    return _cachedIsLargeScreen!;
  }

  Widget _buildTabHeader() {
    bool isLargeScreen = _getIsLargeScreen(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Centered indicator
          SimplePageIndicator(
            pages: _buildPages(context),
            pageController: _pageController,
          ),
          // Button only on small screens, positioned at the end
          if (!isLargeScreen)
            Positioned(
              right: 0,
              child: IconButton(
                icon: Icon(_isExpanded ? Icons.expand_more : Icons.expand_less),
                onPressed: _toggleExpand,
                tooltip: _isExpanded ? AppLocalizations.of(context)!.collapseTooltip : AppLocalizations.of(context)!.expandTooltip,
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
          Expanded(
            flex: 1,
            child: RepaintBoundary(
              child: SizedBox(
                height: double.infinity, // 给Player提供明确的高度约束
                child: const Center( // 添加Center组件使Player垂直居中
                  child: Player(isLargeScreen: true),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                RepaintBoundary(child: _buildTabHeader()),
                Expanded(
                  child: RepaintBoundary(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: _onPageChangedOptimized,
                      children: _buildPages(context).map((page) => page.page).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
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
    bool isLargeScreen = _getIsLargeScreen(context);

    if (isLargeScreen) {
      // On large screens, always use the side-by-side layout
      return _buildCollapsedLargeLayout();
    } else {
      // On small screens, maintain a single PageView while animating other parts
      return Scaffold(
        body: Column(
          children: [
            // Only animate this top part - simplified animation
            RepaintBoundary(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150), // 减少动画时长
                switchInCurve: Curves.easeOut,
                transitionBuilder: (child, animation) {
                  // 简化为仅使用 FadeTransition，移除 SlideTransition 减少计算开销
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: _isExpanded
                  ? KeyedSubtree(
                      key: const ValueKey('expanded_header'),
                      child: GestureDetector(
                        onTap: _toggleExpand,
                        child: const Player(isLargeScreen: false, isMiniPlayer: true),
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('collapsed_header'),
                      child: const Column(
                        children: [
                          Player(isLargeScreen: false),
                          SizedBox(height: 16),
                        ],
                      ),
                    ),
              ),
            ),
            // Tab header stays consistent
            _buildTabHeader(),
            // PageView stays consistent across states
            Expanded(
              child: RepaintBoundary(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChangedOptimized,
                  children: _buildPages(context).map((page) => page.page).toList(),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            HapticFeedback.lightImpact();
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