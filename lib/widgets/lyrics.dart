import 'package:flutter/material.dart';
import 'materialui.dart';

class LyricsWidget extends StatelessWidget {
  final List<String> lyrics = [
    "Supersonic (yeah, ooh), in your orbit (yeah, ah)",
    "And I'm bad (uh), diabolic (uh)",
    "Bottle rocket (ooh, yeah) on the carpet (yeah)",
    "Threw it back and he caught it",
    "I go soprano, baby, go down low",
    // ... 其他歌词行
  ];
  
  final int currentLineIndex;

  LyricsWidget({
    required this.currentLineIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const IconHeader(icon: Icons.lyrics, text: "LYRICS"),
        Expanded(
          child: ListView.builder(
            itemCount: lyrics.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 24.0,
                ),
                child: Text(
                  lyrics[index],
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: index < currentLineIndex
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : index == currentLineIndex
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondaryContainer,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.left,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
