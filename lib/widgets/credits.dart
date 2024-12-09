import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';

class CreditsWidget extends StatelessWidget {
  const CreditsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final track = context.select<SpotifyProvider, Map<String, dynamic>?>(
      (provider) => provider.currentTrack?['item']
    );

    // Get artists information
    final artists = (track?['artists'] as List?)
        ?.map((artist) => artist['name'] as String)
        .toList() ?? ['Unknown Artist'];

    return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Credits',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // Artists Section
            _buildSection(
              context,
              title: 'Artists',
              items: artists,
            ),
            
            // Note about additional credits
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Note: Detailed songwriter and producer credits are not available through the standard Spotify API.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildSection(BuildContext context, {
    required String title,
    required List<String> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Text(item),
        )),
      ],
    );
  }
}
