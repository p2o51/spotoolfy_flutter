import 'package:flutter/material.dart';

class StatsCard extends StatelessWidget {
  final String firstRecordedValue;
  final String firstRecordedUnit;
  final IconData trendIcon;
  final IconData latestRatingIcon;
  final String lastPlayedLine1;
  final String lastPlayedLine2;

  const StatsCard({
    super.key,
    required this.firstRecordedValue,
    required this.firstRecordedUnit,
    required this.trendIcon,
    required this.latestRatingIcon,
    required this.lastPlayedLine1,
    required this.lastPlayedLine2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    // Define colors based on the image (adjust as needed)
    final cardBackgroundColor = colorScheme.surfaceContainerLow; // Light purple
    final dividerColor = colorScheme.tertiaryContainer; // Light pink
    final iconBackgroundColor = colorScheme.primary; // Dark purple
    final primaryTextColor = colorScheme.primary; // Or a specific dark color
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Section (First Recorded)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1st Record',
                style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                firstRecordedValue,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: iconBackgroundColor, // Use dark purple for emphasis
                  height: 1.1,
                ),
              ),
              Text(
                firstRecordedUnit,
                style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
              ),
            ],
          ),

          // Right Section (Last Played)
          Row(
             mainAxisSize: MainAxisSize.min,
            children: [
               Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4.0),
                  margin: const EdgeInsets.only(right: 8.0),
                 decoration: BoxDecoration(
                   color: dividerColor,
                   borderRadius: BorderRadius.circular(18.0),
                 ),
                 child: Icon(
                   trendIcon,
                   size: 24.0,
                   color: iconBackgroundColor,
                 ),
               ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Icon(
                  latestRatingIcon,
                  color: theme.colorScheme.onPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12.0),
              Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Last Play',
                     style: textTheme.labelMedium?.copyWith(color: secondaryTextColor),
                  ),
                   const SizedBox(height: 2),
                  Text(
                    lastPlayedLine1,
                     style: textTheme.bodyMedium?.copyWith(
                       color: iconBackgroundColor,
                       height: 1.2,
                    ),
                  ),
                  Text(
                    lastPlayedLine2,
                     style: textTheme.bodyMedium?.copyWith(
                       color: iconBackgroundColor,
                       height: 1.2,
                     ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
} 