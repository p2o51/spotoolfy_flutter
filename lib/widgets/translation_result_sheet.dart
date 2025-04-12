import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import '../services/settings_service.dart'; // Import TranslationStyle and SettingsService

// Helper to get display name for style (copied from settings_service or shared location)
String _getTranslationStyleDisplayName(TranslationStyle style) {
  switch (style) {
    case TranslationStyle.faithful:
      return 'Faithful';
    case TranslationStyle.melodramaticPoet:
      return 'Melodramatic Poet';
    case TranslationStyle.machineClassic:
      return 'Machine Classic';
  }
}

class TranslationResultSheet extends StatefulWidget {
  final String originalLyrics;
  final String translatedLyrics;
  final Future<String?> Function() onReTranslate;
  final TranslationStyle translationStyle; // Add style parameter

  const TranslationResultSheet({
    Key? key,
    required this.originalLyrics,
    required this.translatedLyrics,
    required this.onReTranslate,
    required this.translationStyle, // Make style required
  }) : super(key: key);

  @override
  State<TranslationResultSheet> createState() => _TranslationResultSheetState();
}

class _TranslationResultSheetState extends State<TranslationResultSheet> {
  bool _isTranslating = false;
  String? _translationError;
  late String _currentTranslatedLyrics;

  // Instantiate SettingsService here or within the function where needed
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _currentTranslatedLyrics = widget.translatedLyrics;
  }

  Future<void> _handleReTranslate() async {
     if (_isTranslating) return;

    setState(() {
      _isTranslating = true;
      _translationError = null;
    });

    try {
      final newTranslation = await widget.onReTranslate();
      if (mounted) {
        setState(() {
          if (newTranslation != null) {
            _currentTranslatedLyrics = newTranslation;
            _translationError = null;
          } else {
            _translationError = 'Failed to re-translate. Please try again.';
          }
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _translationError = 'Error: ${e.toString()}';
          _isTranslating = false;
        });
      }
    }
  }

  // Helper function to copy lyrics - Reads setting now
  Future<void> _copyToClipboard(bool isWideScreen) async {
    // print('[DEBUG] _copyToClipboard called.'); // DEBUG REMOVED

    // Fetch the setting
    bool copyAsSingleLine = false;
    try {
      copyAsSingleLine = await _settingsService.getCopyLyricsAsSingleLine();
    } catch (e) {
      print("Error reading copy setting: $e");
      // Use default (false) if error
    }

    // Adapt logic based on screen width
    final lyricsToCopy = isWideScreen
        ? _currentTranslatedLyrics // On wide screens, always copy translation
        : (_translationError == null ? _currentTranslatedLyrics : widget.originalLyrics); // Use old logic only if narrow
    // We need a way to know if translation is "shown" on narrow screens.
    // Let's rethink the state. Keep _showTranslated for narrow screens.
    // Re-add _showTranslated state variable.
    // final lyricsToCopy = isWideScreen
    //     ? _currentTranslatedLyrics
    //     : (_showTranslated ? _currentTranslatedLyrics : widget.originalLyrics);

    String textToCopy;

    if (!copyAsSingleLine) { // Default: copy with line breaks
      textToCopy = lyricsToCopy;
    } else { // If setting is true: copy as single line
      // Replace multiple newlines/spaces with a single space and trim
      textToCopy = lyricsToCopy.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    Clipboard.setData(ClipboardData(text: textToCopy));
    // Check if the widget is still mounted before showing SnackBar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lyrics copied${copyAsSingleLine ? ' as single line' : ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen width and layout mode
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    // Decide which lyrics and title to show for narrow layout (only)
    // This state is still needed for narrow screens
    final lyricsToShow = _showTranslated ? _currentTranslatedLyrics : widget.originalLyrics;
    final titleLabel = _showTranslated ? 'Translation' : 'Original';

    // Common variables
    final screenHeight = MediaQuery.of(context).size.height;
    final initialHeight = screenHeight * 0.6;
    final maxHeight = screenHeight * 0.9;

    return DraggableScrollableSheet(
      initialChildSize: initialHeight / screenHeight,
      minChildSize: 0.3,
      maxChildSize: maxHeight / screenHeight,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
              // Drag Handle
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              // Header Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title - Adapt based on screen width
                    Text(
                      isWideScreen ? 'Lyrics' : titleLabel, // General title for wide screens
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Action Buttons Row
                    Row(
                      children: [
                        // Retranslate Button
                        _isTranslating
                          ? const SizedBox(
                              width: 36,
                              height: 36,
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton.filledTonal(
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip: 'Re-translate',
                              onPressed: _handleReTranslate,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                        const SizedBox(width: 4),
                        // Copy Button - Pass isWideScreen
                        IconButton.filledTonal(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: 'Copy Lyrics', // Updated tooltip
                          onPressed: () => _copyToClipboard(isWideScreen), // Pass screen type
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                        // Conditionally show Toggle Button only on narrow screens
                        if (!isWideScreen) ...[
                           const SizedBox(width: 4), // Reverted spacing
                           // Toggle Translate/Original Button - Revert visual density
                           _showTranslated
                            ? IconButton.filledTonal(
                                key: const ValueKey('toggle_button_selected'),
                                icon: const Icon(Icons.translate, size: 20),
                                tooltip: 'Show Original',
                                onPressed: () {
                                  setState(() => _showTranslated = !_showTranslated);
                                },
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('toggle_button_unselected'),
                                icon: const Icon(Icons.translate, size: 20),
                                tooltip: 'Show Translation',
                                onPressed: () {
                                  setState(() => _showTranslated = !_showTranslated);
                                },
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(8),
                                  foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                        ],
                      ],
                    )
                  ],
                ),
              ),
              const Divider(),
              // Conditional Layout for Lyrics Content
              Expanded(
                child: isWideScreen
                    ? _buildWideLayout(context, scrollController) // Pass context
                    : _buildNarrowLayout(context, scrollController), // Pass context
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Layout Builders ---

  // Narrow Layout (Existing Logic)
  Widget _buildNarrowLayout(BuildContext context, ScrollController scrollController) {
    final lyricsToShow = _showTranslated ? _currentTranslatedLyrics : widget.originalLyrics;
    final styleDisplayName = _getTranslationStyleDisplayName(widget.translationStyle);
    final attributionText = "Translated by Gemini 2.0 Flash\nSpirit: $styleDisplayName";
    final theme = Theme.of(context);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        // AnimatedSwitcher for Lyrics
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            );
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.05),
              end: Offset.zero,
            ).animate(curvedAnimation);
            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey<bool>(_showTranslated), // Key remains important here
            alignment: Alignment.topLeft,
            child: SelectableText(
              _translationError ?? lyricsToShow,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.4,
                color: _translationError != null ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Attribution Row (Conditional on showing translation)
        if (_showTranslated && _translationError == null)
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attributionText,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 40), // Bottom padding
      ],
    );
  }

  // Wide Layout (New Side-by-Side Logic)
  Widget _buildWideLayout(BuildContext context, ScrollController scrollController) {
    final theme = Theme.of(context);
    final styleDisplayName = _getTranslationStyleDisplayName(widget.translationStyle);
    final attributionText = "Translated by Gemini 2.0 Flash\nSpirit: $styleDisplayName";

    // Define consistent padding
    const edgeInsets = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    const bottomPadding = SizedBox(height: 40);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Align content to the top
      children: [
        // Left Column: Translation
        Expanded(
          child: ListView( // Use the main scroll controller for the primary (translated) content
            controller: scrollController,
            padding: edgeInsets,
            children: [
              Text(
                'Translation',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _translationError ?? _currentTranslatedLyrics,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.4,
                  color: _translationError != null ? theme.colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 16),
              // Show attribution only if no error
              if (_translationError == null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 24, // Keep size consistent
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        attributionText,
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                        // Removed overflow ellipsis to show full text if possible
                      ),
                    ),
                  ],
                ),
              bottomPadding, // Padding at the bottom
            ],
          ),
        ),
        // Right Column: Original
        Expanded(
          // Use SingleChildScrollView + Column for independent scrolling if content overflows
          child: SingleChildScrollView(
             padding: edgeInsets.copyWith(left: 12), // Add some left padding to simulate separation
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                   'Original',
                   style: theme.textTheme.titleMedium?.copyWith(
                     fontWeight: FontWeight.w500,
                      color: theme.colorScheme.secondary // Use secondary color for distinction
                   ),
                 ),
                 const SizedBox(height: 8),
                 SelectableText(
                   widget.originalLyrics,
                   style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                 ),
                 bottomPadding, // Padding at the bottom
               ],
             ),
          ),
        ),
      ],
    );
  }

  // Re-add _showTranslated state variable and initState update
  bool _showTranslated = true; // Default to showing translated initially
}