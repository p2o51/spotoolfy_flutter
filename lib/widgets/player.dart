//player.dart
import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';

class Player extends StatefulWidget {
  const Player({super.key});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  bool isPlaying = true;
  int selectedIndex = 1;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: Image.asset('assets/examples/CXOXO.png'),
            ),
          ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              IconHeader(icon: Icons.music_note, text: 'NOWPLAYING'),
            ],),
          ),
          Positioned(
            bottom: 64,
            right: 0,
            child: PlayButton(
              isPlaying: isPlaying,
              onPressed: () {
                setState(() {
                  isPlaying = !isPlaying;
                });
              },
            ),
          ),
          Positioned(
            bottom: 0,
            left: 64,
            child: MyButton(width: 64, height: 64, radius: 20, icon: Icons.skip_next_rounded, onPressed: (){}),
          ),
            ],
          ),
          const SizedBox(height: 8,),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 48, 0), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const HeaderAndFooter(header: 'Godspeed', footer: 'Camila Cabello'),
                    IconButton.filled(onPressed: (){}, icon: const Icon(Icons.favorite_outline_rounded)),
                  ],
                ),
            ],),
          ),
        ],
      ),
    );
  }
}

class PlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const PlayButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Container(
        width: 96,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(32.0),
          border: Border.all(
            color: Theme.of(context).colorScheme.primaryContainer,
            width: 4,
          ),
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
        ),
      ),
    );
  }
}
