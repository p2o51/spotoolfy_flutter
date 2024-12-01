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

  @override
  Widget build(BuildContext context) {
    return Consumer<FirestoreProvider>(
      builder: (context, firestoreProvider, child) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Roam',
                style: TextStyle(
                  fontFamily: 'Derivia',
                  fontSize: 96,
                  height: 0.9,
                ),
              ),
              const Text(
                'ing',
                style: TextStyle(
                  fontFamily: 'Derivia',
                  fontSize: 64,
                  height: 0.9,
                ),
              ),
              const SizedBox(height: 32),
              if (firestoreProvider.isLoading)
                const CircularProgressIndicator()
              else if (firestoreProvider.randomThought == null)
                Text(
                  '还没有任何笔记...',
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: GestureDetector(
                    onTap: () => firestoreProvider.fetchRandomThought(),
                    child: Column(
                      children: [
                        Text(
                          firestoreProvider.randomThought!['content'],
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${firestoreProvider.randomThought!['artistName']} - '
                          '${firestoreProvider.randomThought!['trackName']}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          firestoreProvider.randomThought!['rating'],
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Touch to roam',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}