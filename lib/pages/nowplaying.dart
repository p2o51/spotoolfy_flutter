//nowplaying.dart
import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/player.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
class NowPlaying extends StatelessWidget {
  const NowPlaying({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SingleChildScrollView(
        child: Column(
          children: [
            Player(),
            SizedBox(height: 16),
            Ratings(),
            SizedBox(height: 16),
            NotesDisplay(),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: (){}, 
        child: const Icon(Icons.add),
      ),
    );
  }
}