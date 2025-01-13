import 'package:flutter/material.dart';

class SimplePageIndicator extends StatefulWidget {
  final List<PageData> pages;
  final PageController pageController;

  const SimplePageIndicator({
    Key? key,
    required this.pages,
    required this.pageController,
  }) : super(key: key);

  @override
  State<SimplePageIndicator> createState() => _SimplePageIndicatorState();
}

class _SimplePageIndicatorState extends State<SimplePageIndicator> {
  late int currentPage = widget.pageController.initialPage;

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_onPageChange);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onPageChange);
    super.dispose();
  }

  void _onPageChange() {
    final page = widget.pageController.page?.round() ?? 0;
    if (page != currentPage) {
      setState(() {
        currentPage = page;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 页面指示器点
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.pages.length,
            (index) => Container(
              width: 8,
              height: 8,
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index == currentPage
                    ? Theme.of(context).colorScheme.primary // 选中的紫色
                    : Theme.of(context).colorScheme.primaryContainer, // 未选中的浅紫色
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        // 图标和文字
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.pages[currentPage].icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(width: 8),
            Text(
              widget.pages[currentPage].title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 14,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 页面数据模型
class PageData {
  final String title;
  final IconData icon;
  final Widget page;

  PageData({
    required this.title,
    required this.icon,
    required this.page,
  });
}

// 使用示例
class ExamplePage extends StatefulWidget {
  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final PageController _pageController = PageController();
  final List<PageData> _pages = [
    PageData(
      title: '歌词',
      icon: Icons.music_note,
      page: Center(child: Text('歌词页面')),
    ),
    PageData(
      title: '曲谱',
      icon: Icons.queue_music,
      page: Center(child: Text('曲谱页面')),
    ),
    PageData(
      title: '设置',
      icon: Icons.settings,
      page: Center(child: Text('设置页面')),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true, // 这个属性使其在滚动到顶部时固定
          delegate: _StickyTabDelegate(
            child: SimplePageIndicator(
              pages: _pages,
              pageController: _pageController,
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
    );
  }
}

// 添加这个新类来处理粘性效果
class _StickyTabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  
  _StickyTabDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  double get maxExtent => 80.0; // 调整这个高度以适应您的标签栏

  @override
  double get minExtent => 80.0; // 通常与maxExtent相同，除非您想要动态高度

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}