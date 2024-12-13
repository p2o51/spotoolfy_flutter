import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/providers/firestore_provider.dart';
import 'package:spotoolfy_flutter/providers/spotify_provider.dart';

class ThoughtsView extends StatefulWidget {
  const ThoughtsView({super.key});

  @override
  ThoughtsViewState createState() => ThoughtsViewState();
}

class ThoughtsViewState extends State<ThoughtsView> {
  bool showPlaylists = true;
  bool showAlbums = true;

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpotifyProvider, FirestoreProvider>(
      builder: (context, spotifyProvider, firestoreProvider, child) {
        final items = [
          if (showPlaylists) 
            ...firestoreProvider.recentPlayContexts
                .where((context) => context['type'] == 'playlist'),
          if (showAlbums) 
            ...firestoreProvider.recentPlayContexts
                .where((context) => context['type'] == 'album'),
        ];

        return RefreshIndicator(
          onRefresh: () async {
            await spotifyProvider?.refreshRecentlyPlayed();
          },
          child: ListView(
            // ... 其余代码保持不变
          ),
        );
      },
    );
  }
}