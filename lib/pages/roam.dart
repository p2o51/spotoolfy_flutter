//roam.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../providers/firestore_provider.dart'; // Remove old provider
import '../providers/local_database_provider.dart'; // Import new provider

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
                SliverAppBar(
                  expandedHeight: 120,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      'Roaming',
                      style: TextStyle(
                        fontFamily: 'Derivia',
                        fontSize: 32,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    centerTitle: true,
                  ),
                ),
                // Use the new provider's loading state
                if (localDbProvider.isLoading)
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
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  // Use correct map key for artist name
                                                  '${record['artistName'] ?? 'Unknown Artist'}',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.secondary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
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