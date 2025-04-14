//roam.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../providers/firestore_provider.dart'; // Remove old provider
import '../providers/local_database_provider.dart'; // Import new provider
import 'package:flutter/services.dart'; // Import for HapticFeedback if needed later
import 'package:cached_network_image/cached_network_image.dart'; // Import CachedNetworkImage

class Roam extends StatefulWidget {
  const Roam({super.key});

  @override
  State<Roam> createState() => _RoamState();
}

class _RoamState extends State<Roam> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch initial data using the new provider
      Provider.of<LocalDatabaseProvider>(context, listen: false).fetchRandomRecords(15); // Fetch 15 records initially
    });
  }

  Future<void> _refreshThoughts() async {
    // Refresh data using the new provider
    await Provider.of<LocalDatabaseProvider>(context, listen: false).fetchRandomRecords(15); // Fetch 15 records on refresh
  }

  @override
  Widget build(BuildContext context) {
    // Consume the new provider
    return Consumer<LocalDatabaseProvider>(
      builder: (context, localDbProvider, child) {
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refreshThoughts,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Add the new NotesCarouselView here
                SliverToBoxAdapter(
                  child: Padding(
                    // Add some vertical padding if needed
                    padding: const EdgeInsets.symmetric(vertical: 16.0), 
                    child: NotesCarouselView(),
                  ),
                ),
                // Use the new provider's loading state
                if (localDbProvider.isLoading && localDbProvider.randomRecords.isEmpty) // Show loading only if records are empty
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                // Use the new provider's data list
                else if (localDbProvider.randomRecords.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        '还没有任何笔记...',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          // Use the new provider's data list
                          if (index >= localDbProvider.randomRecords.length) {
                            return null;
                          }
                          
                          // Access data using map keys
                          final record = localDbProvider.randomRecords[index];
                          final isFirst = index == 0;
                          final isLast = index == localDbProvider.randomRecords.length - 1;
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                            child: Card(
                              elevation: 0,
                              color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(isFirst ? 24 : 8),
                                  topRight: Radius.circular(isFirst ? 24 : 8),
                                  bottomLeft: Radius.circular(isLast ? 24 : 8),
                                  bottomRight: Radius.circular(isLast ? 24 : 8),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.note_alt_outlined,
                                          size: 32,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            // Use correct map key for note content
                                            record['noteContent'] ?? '', // Handle potential null
                                            style: Theme.of(context).textTheme.bodyLarge,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 48.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  // Use correct map key for track name
                                                  '${record['trackName'] ?? 'Unknown Track'}',
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).colorScheme.primary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                ),
                                                Text(
                                                  // Use correct map key for artist name
                                                  '${record['artistName'] ?? 'Unknown Artist'}',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.secondary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Display rating icon based on integer value
                                        () { // Wrap the logic in a builder function or IIFE
                                          final dynamic ratingRaw = record['rating']; // Get the raw value first
                                          int? ratingValue;

                                          if (ratingRaw is int) {
                                            ratingValue = ratingRaw;
                                          } else if (ratingRaw is String) {
                                            // If it's a string (old data), treat it as the default rating 3
                                            ratingValue = 3;
                                          }
                                          // If ratingRaw is null or other type, ratingValue remains null

                                          IconData ratingIcon;
                                          switch (ratingValue) { // Use the potentially parsed value
                                            case 0:
                                              ratingIcon = Icons.thumb_down_outlined;
                                              break;
                                            case 5:
                                              ratingIcon = Icons.whatshot_outlined;
                                              break;
                                            case 3:
                                            default:
                                              ratingIcon = Icons.sentiment_neutral_rounded;
                                              break;
                                          }
                                          // Return the Icon widget directly
                                          return Icon(ratingIcon, color: Theme.of(context).colorScheme.primary, size: 20);
                                        }(), // Immediately invoke the function to get the Icon widget
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        // Use the new provider's data list length
                        childCount: localDbProvider.randomRecords.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 100), // Keep padding at the bottom
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Add the new NotesCarouselView Widget ---

class NotesCarouselView extends StatelessWidget {
  const NotesCarouselView({super.key});

  // Helper to build the rating icon
  Widget _buildRatingIcon(BuildContext context, dynamic ratingRaw) {
      int? ratingValue;
      if (ratingRaw is int) {
        ratingValue = ratingRaw;
      } else if (ratingRaw is String) {
        ratingValue = 3; // Default for old string data
      }

      IconData ratingIcon;
      switch (ratingValue) {
        case 0:
          ratingIcon = Icons.thumb_down_outlined;
          break;
        case 5:
          ratingIcon = Icons.whatshot_outlined;
          break;
        case 3:
        default:
          ratingIcon = Icons.sentiment_neutral_rounded;
          break;
      }
      return Icon(ratingIcon, color: Theme.of(context).colorScheme.primary, size: 20);
  }


  @override
  Widget build(BuildContext context) {
    final localDbProvider = Provider.of<LocalDatabaseProvider>(context);
    final randomRecords = localDbProvider.randomRecords;

    // Don't show carousel if loading or no records
    if (localDbProvider.isLoading || randomRecords.isEmpty) {
      // You might want a placeholder, but SizedBox.shrink() keeps it clean
      // Or return _buildLoadingCarousel(context); if you want a loading state
       return const SizedBox.shrink(); 
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        // Adjust height and weights based on screen width, similar to MyCarouselView
        final carouselHeight = screenWidth > 900 ? 250.0 : 180.0; 
        final flexWeights = screenWidth > 900
            ? const [1, 2, 5, 2, 1] // Updated for > 900
            : screenWidth > 600
            ? const [1, 4, 1]   // Updated for 600-900
            : const [1, 5, 1];  // Updated for < 600

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: carouselHeight),
            child: CarouselView.weighted(
              flexWeights: flexWeights,
              shrinkExtent: 0, // Similar to MyCarouselView
              itemSnapping: true,
              // Add onTap handler if needed in the future
              // onTap: (index) { ... } 
              children: randomRecords.map((record) {
                final isFirst = randomRecords.first == record;
                final isLast = randomRecords.last == record;
                final imageUrl = record['albumCoverUrl'] as String?;
                final fallbackColor = Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.8);

                // Building the card content similar to the list item
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect( // Use ClipRRect for rounded corners on the Stack
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand, // Make Stack fill the container
                      children: [
                        // Background Image
                        if (imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: fallbackColor),
                            errorWidget: (context, url, error) => Container(
                              color: fallbackColor,
                              child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
                            ),
                          )
                        else
                          Container(color: fallbackColor), // Fallback background

                        // Content Overlay (with semi-transparent background)
                        Container(
                          // Add a dark overlay for better text contrast
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.7)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          padding: const EdgeInsets.all(16.0), 
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Display Note Content (allow multiple lines, limit height)
                              Expanded( // Use Expanded to fill available space
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.format_quote_rounded, // Use a quote icon
                                      size: 20, // Reduced size
                                      color: Colors.white.withOpacity(0.9), // Adjust color for contrast
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        record['noteContent'] ?? '',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.white, // Adjust color for contrast
                                        ),
                                        overflow: TextOverflow.ellipsis, // Allow ellipsis
                                        maxLines: 3, // Allow wrapping up to 3 lines
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Divider or SizedBox
                              Divider(color: Colors.white.withOpacity(0.3)),
                              const SizedBox(height: 8),
                              // Display Track Info and Rating
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${record['trackName'] ?? 'Unknown Track'}',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white, // Adjust color for contrast
                                          ),
                                          maxLines: 1, // Keep maxLines 1
                                          overflow: TextOverflow.ellipsis, // Allow ellipsis
                                        ),
                                        Text(
                                          '${record['artistName'] ?? 'Unknown Artist'}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.white.withOpacity(0.8), // Adjust color for contrast
                                          ),
                                          maxLines: 1, // Keep maxLines 1
                                          overflow: TextOverflow.ellipsis, // Allow ellipsis
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Rating Icon (adjust color?)
                                  _buildRatingIcon(context, record['rating']), // Re-use existing helper
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // Optional: Add a loading carousel placeholder like in MyCarouselView
  // Widget _buildLoadingCarousel(BuildContext context) { ... }
}