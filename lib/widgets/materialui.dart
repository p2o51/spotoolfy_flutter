import 'package:flutter/material.dart';

class MyButton extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final IconData icon;
  final void Function() onPressed;

  const MyButton({super.key, required this.width, required this.height, required this.radius, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
    );
  }
}

class IconHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const IconHeader({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 16
        ),
        const SizedBox(width: 8),
        Flexible(  // 添加 Flexible 来允许文本在需要时换行或收缩
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 2.0,
            ),

          ),
        ),
      ],
    );
  }
}

class HeaderAndFooter extends StatelessWidget {
  final String header;
  final String footer;
  const HeaderAndFooter({super.key, required this.header, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(header, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 22, fontWeight: FontWeight.bold),),
        const SizedBox(width: 8,),
        Text(footer, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 22, fontWeight: FontWeight.normal),),
      ],
    );
  }
}


class Ratings extends StatefulWidget {
  final String initialRating;
  final Function(int) onRatingChanged;

  const Ratings({
    super.key, 
    required this.initialRating,
    required this.onRatingChanged,
  });

  @override
  State<Ratings> createState() => _RatingsState();
}

class _RatingsState extends State<Ratings> {
  late int selectedIndex;
  
  @override
  void initState() {
    super.initState();
    selectedIndex = _getRatingIndex(widget.initialRating);
  }

  int _getRatingIndex(String rating) {
    switch (rating) {
      case 'bad': return 0;
      case 'fire': return 2;
      default: return 1; // 'good'
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, icon: Icon(Icons.thumb_down_outlined)),
        ButtonSegment(value: 1, icon: Icon(Icons.sentiment_neutral_rounded)),
        ButtonSegment(value: 2, icon: Icon(Icons.whatshot_outlined)),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (Set<int> newSelection) {
        setState(() {
          selectedIndex = newSelection.first;
          widget.onRatingChanged(selectedIndex);
        });
      },
    );
  }
}