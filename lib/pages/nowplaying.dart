//nowplaying.dart
import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/player.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
import 'package:spotoolfy_flutter/widgets/add_note.dart';

class NowPlaying extends StatelessWidget {
  const NowPlaying({super.key});

  @override
  Widget build(BuildContext context) {
    // 检查屏幕宽度：大屏幕
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: isLargeScreen
          ? Row(
              children: [
                // 左侧固定部分
                Expanded(
                  flex: 1,
                  child: Column(
                    children: const [
                      Player(),
                      SizedBox(height: 16),
                      Ratings(),
                    ],
                  ),
                ),
                // 右侧可滚动部分
                Expanded(
                  flex: 1,
                  child: SingleChildScrollView(
                    child: Column(
                      children: const [
                        NotesDisplay(),
                        SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : const SingleChildScrollView(
              child: Column(
                children: [
                  Player(),
                  SizedBox(height: 16),
                  Ratings(),
                  SizedBox(height: 16),
                  NotesDisplay(),
                  SizedBox(height: 80),
                ],
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