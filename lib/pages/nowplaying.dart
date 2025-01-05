//nowplaying.dart
import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/player.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import 'package:spotoolfy_flutter/widgets/add_note.dart';
import 'package:spotoolfy_flutter/widgets/queue.dart';
import 'package:spotoolfy_flutter/widgets/lyrics.dart';

class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});

  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> with AutomaticKeepAliveClientMixin {
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
              child: DefaultTabController(
                length: 3,
                initialIndex: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.comment_rounded)),
                        Tab(icon: Icon(Icons.queue_music_rounded)),
                        Tab(icon: Icon(Icons.lyrics_rounded)),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          SingleChildScrollView(
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
                          const SingleChildScrollView(
                            child: QueueDisplay(),
                          ),
                          LyricsWidget(),
                        ],
                      ),
                    ),
                  ],
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
    } else {
      return Scaffold(
        body: DefaultTabController(
          length: 3,
          initialIndex: 2,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const Player(isLargeScreen: false),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.comment)),
                        Tab(icon: Icon(Icons.queue_music)),
                        Tab(icon: Icon(Icons.lyrics)),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              children: [
                SingleChildScrollView(
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
                const SingleChildScrollView(
                  child: QueueDisplay(),
                ),
                LyricsWidget(),
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