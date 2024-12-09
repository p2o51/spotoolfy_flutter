//nowplaying.dart
import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/player.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import 'package:spotoolfy_flutter/widgets/add_note.dart';
import 'package:spotoolfy_flutter/widgets/queue.dart';
import 'package:spotoolfy_flutter/widgets/lyrics.dart';
import 'package:spotoolfy_flutter/widgets/credits.dart';
class NowPlaying extends StatelessWidget {
  const NowPlaying({super.key});

  @override
  Widget build(BuildContext context) {
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: DefaultTabController(
        length: 4,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const Player(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              const SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    tabs: [
                      Tab(text: 'THOUGHTS'),
                      Tab(text: 'QUEUE'),
                      Tab(text: 'LYRICS'),
                      Tab(text: 'CREDITS'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              // THOUGHTS 内容
              isLargeScreen
                  ? Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Column(
                            children: [
                              Ratings(
                                initialRating: 'good',
                                onRatingChanged: (rating) {
                                  // Handle rating change if needed
                                },
                              ),
                            ],
                          ),
                        ),
                        const Expanded(
                          flex: 1,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                NotesDisplay(),
                                SizedBox(height: 80),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
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
              // QUEUE 内容
              const SingleChildScrollView(
                child: QueueDisplay(),
              ),
              // LYRICS 内容
              LyricsWidget(currentLineIndex: 2),
              
              // CREDITS 内容
              const CreditsWidget(),
            ],
          ),
        ),
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

// 添加这个辅助类来处理 TabBar 的固定效果
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  const _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}