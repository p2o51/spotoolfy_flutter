import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard

class TranslationResultSheet extends StatefulWidget {
  final String originalLyrics;
  final String translatedLyrics;

  const TranslationResultSheet({
    Key? key,
    required this.originalLyrics,
    required this.translatedLyrics,
  }) : super(key: key);

  @override
  State<TranslationResultSheet> createState() => _TranslationResultSheetState();
}

class _TranslationResultSheetState extends State<TranslationResultSheet> {
  bool _showTranslated = true;

  @override
  Widget build(BuildContext context) {
    final lyricsToShow = _showTranslated ? widget.translatedLyrics : widget.originalLyrics;
    final titleLabel = _showTranslated ? 'Translation' : 'Original';

    // Calculate initial size and max size for the sheet
    final screenHeight = MediaQuery.of(context).size.height;
    final initialHeight = screenHeight * 0.6; // Start at 60% of screen height
    final maxHeight = screenHeight * 0.9;    // Allow up to 90%

    return DraggableScrollableSheet(
      initialChildSize: initialHeight / screenHeight,
      minChildSize: 0.3, // Minimum height
      maxChildSize: maxHeight / screenHeight,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface, // Use surface color
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      titleLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        // Re-translate Button
                        IconButton.filledTonal(
                          icon: const Icon(Icons.refresh, size: 20), // Smaller icon size
                          tooltip: 'Re-translate (closes sheet)',
                          onPressed: () {
                            // Simple action: close the sheet to allow re-triggering
                            // TODO: Implement direct re-translation if needed via callback
                            Navigator.pop(context);
                          },
                           style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8), // Adjust padding
                          ),
                        ),
                        const SizedBox(width: 4), // Spacing
                        // Copy Button
                        IconButton.filledTonal(
                          icon: const Icon(Icons.copy, size: 20), // Smaller icon size
                          tooltip: 'Copy Lyrics',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: lyricsToShow));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lyrics copied to clipboard')),
                            );
                          },
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8), // Adjust padding
                          ),
                        ),
                         const SizedBox(width: 4), // Spacing
                        // Toggle Button - Use different button styles for selected/unselected
                        _showTranslated
                          ? IconButton.filledTonal( // Selected state: Filled Tonal
                              key: const ValueKey('toggle_button_selected'), // Add key for smooth transition
                              icon: const Icon(Icons.translate, size: 20),
                              tooltip: 'Show Original',
                              onPressed: () {
                                setState(() {
                                  _showTranslated = !_showTranslated;
                                });
                              },
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                            )
                          : IconButton( // Unselected state: Standard IconButton (appears outlined/borderless)
                              key: const ValueKey('toggle_button_unselected'), // Add key for smooth transition
                              icon: const Icon(Icons.translate, size: 20),
                              tooltip: 'Show Translation',
                              onPressed: () {
                                setState(() {
                                  _showTranslated = !_showTranslated;
                                });
                              },
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant, // Use a less prominent color
                              ),
                            ),
                      ],
                    )
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollController, // Important for DraggableScrollableSheet
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300), // Animation duration
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        // Apply an easing curve
                        final curvedAnimation = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut, // Use an easing curve
                        );

                        // Combine Fade and Slide transition using the curved animation
                        final slideAnimation = Tween<Offset>(
                          begin: const Offset(0.0, 0.05),
                          end: Offset.zero,
                        ).animate(curvedAnimation); // Use curvedAnimation

                        return FadeTransition(
                          opacity: curvedAnimation, // Use curvedAnimation
                          child: SlideTransition(
                            position: slideAnimation,
                            child: child,
                          ),
                        );
                      },
                      // Wrap SelectableText in a Container and apply key here
                      child: Container(
                        key: ValueKey<bool>(_showTranslated), // Key on the Container
                        alignment: Alignment.topLeft, // Ensure text alignment
                        child: SelectableText(
                          lyricsToShow,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.4, // Adjust line height for readability
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40), // Add padding at the bottom
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 