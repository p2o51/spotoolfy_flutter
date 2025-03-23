//roam.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';

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
      Provider.of<FirestoreProvider>(context, listen: false).fetchRandomThought();
    });
  }

  Future<void> _refreshThoughts() async {
    await Provider.of<FirestoreProvider>(context, listen: false).fetchRandomThought();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FirestoreProvider>(
      builder: (context, firestoreProvider, child) {
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
                if (firestoreProvider.isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (firestoreProvider.randomThoughts.isEmpty)
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
                          if (index >= firestoreProvider.randomThoughts.length) {
                            return null;
                          }
                          
                          final thought = firestoreProvider.randomThoughts[index];
                          final isFirst = index == 0;
                          final isLast = index == firestoreProvider.randomThoughts.length - 1;
                          
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
                                            thought['content'],
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
                                                  '${thought['trackName']}',
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).colorScheme.primary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${thought['artistName']}',
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
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            thought['rating'],
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: firestoreProvider.randomThoughts.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}