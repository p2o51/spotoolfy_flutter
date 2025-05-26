import 'package:flutter/material.dart';
import 'dart:math' as math; // Add math import

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

class Ratings extends StatelessWidget {
  final int? initialRating;
  final Function(int) onRatingChanged;

  const Ratings({
    super.key,
    required this.initialRating,
    required this.onRatingChanged,
  });

  // Maps the integer rating (0, 3, 5) or null/default (3) to the Segmented Button index (0, 1, 2)
  int _getRatingIndex(int? rating) {
    switch (rating) {
      case 0: // bad
        return 0;
      case 5: // fire
        return 2;
      case 3: // good/neutral (or null/default)
      default:
        return 1; // Default to neutral (index 1) if rating is null, 3, or unexpected
    }
  }

  @override
  Widget build(BuildContext context) {
    // Map the internal rating (0, 3, 5) to the segmented button values (0, 1, 2)
    int selectedValue;
    switch (initialRating) {
      case 0:
        selectedValue = 0;
        break;
      case 5:
        selectedValue = 2;
        break;
      case 3:
      default:
        selectedValue = 1; // Default to neutral
    }

    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, icon: Icon(Icons.thumb_down_outlined)),
        ButtonSegment(value: 1, icon: Icon(Icons.sentiment_neutral_rounded)),
        ButtonSegment(value: 2, icon: Icon(Icons.whatshot_outlined)),
      ],
      selected: {selectedValue}, // Use the mapped value
      onSelectionChanged: (Set<int> newSelection) {
        // Map the selected segment value (0, 1, 2) back to the rating (0, 3, 5)
        int newRating;
        switch (newSelection.first) {
          case 0:
            newRating = 0;
            break;
          case 2:
            newRating = 5;
            break;
          case 1:
          default:
            newRating = 3;
        }
        onRatingChanged(newRating);
      },
      // Optional: Add styling if needed
      // style: SegmentedButton.styleFrom(
      //   selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
      // ),
      showSelectedIcon: false, // Don't show checkmark on selected
    );
  }
}

// --- Wavy Line Divider ---

class WavyDivider extends StatelessWidget {
  final double width;
  final double height;
  final Color? color; // Optional color override
  final double strokeWidth;
  final double waveHeight;
  final double waveFrequency;

  const WavyDivider({
    super.key,
    this.width = double.infinity, // Default to full width
    this.height = 20.0,          // Default height for the paint area
    this.color,                  // Default uses primary color
    this.strokeWidth = 2.0,
    this.waveHeight = 5.0,
    this.waveFrequency = 0.03,
  });

  @override
  Widget build(BuildContext context) {
    // Use the provided color or default to theme's primary color
    final waveColor = color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: WavyLinePainter(
          color: waveColor,
          strokeWidth: strokeWidth,
          waveHeight: waveHeight,
          waveFrequency: waveFrequency,
        ),
      ),
    );
  }
}

// --- Animated Wavy Divider ---

class AnimatedWavyDivider extends StatefulWidget {
  final double width;
  final double height;
  final Color? color;
  final double strokeWidth;
  final double waveHeight;
  final double waveFrequency;
  final bool animate;
  final Duration animationDuration;

  const AnimatedWavyDivider({
    super.key,
    this.width = double.infinity,
    this.height = 20.0,
    this.color,
    this.strokeWidth = 2.0,
    this.waveHeight = 5.0,
    this.waveFrequency = 0.03,
    this.animate = true,
    this.animationDuration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedWavyDivider> createState() => _AnimatedWavyDividerState();
}

class _AnimatedWavyDividerState extends State<AnimatedWavyDivider>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));

    if (widget.animate) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedWavyDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _animationController.repeat();
    } else if (!widget.animate && oldWidget.animate) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveColor = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            painter: AnimatedWavyLinePainter(
              color: waveColor,
              strokeWidth: widget.strokeWidth,
              waveHeight: widget.waveHeight,
              waveFrequency: widget.waveFrequency,
              animationValue: _animation.value,
            ),
          );
        },
      ),
    );
  }
}

// Custom Painter for the Wavy Line
class WavyLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double waveHeight;
  final double waveFrequency; // Controls the density of waves

  WavyLinePainter({
    required this.color, // Color is now required
    this.strokeWidth = 2.0,
    this.waveHeight = 10.0,
    this.waveFrequency = 0.03,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height / 2); // Start in the middle on the left

    for (double x = 0; x <= size.width; x++) {
      // Calculate y using sine wave
      final y = waveHeight * math.sin(waveFrequency * 2 * math.pi * x) + size.height / 2;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WavyLinePainter oldDelegate) {
    // Repaint if any properties change
    return oldDelegate.color != color ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.waveHeight != waveHeight ||
           oldDelegate.waveFrequency != waveFrequency;
  }
}

// Custom Painter for the Animated Wavy Line
class AnimatedWavyLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double waveHeight;
  final double waveFrequency;
  final double animationValue;

  AnimatedWavyLinePainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.waveHeight = 10.0,
    this.waveFrequency = 0.03,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height / 2);

    // 计算波浪的相位偏移，创建左右移动效果
    final phaseOffset = animationValue * 2 * math.pi;

    for (double x = 0; x <= size.width; x++) {
      // 添加相位偏移让波浪左右移动
      final y = waveHeight * math.sin(waveFrequency * 2 * math.pi * x + phaseOffset) + size.height / 2;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant AnimatedWavyLinePainter oldDelegate) {
    return oldDelegate.color != color ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.waveHeight != waveHeight ||
           oldDelegate.waveFrequency != waveFrequency ||
           oldDelegate.animationValue != animationValue;
  }
}