import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotoolfy_flutter/providers/firestore_provider.dart';
import 'package:spotoolfy_flutter/widgets/notes.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';

class ThoughtsView extends StatefulWidget {
  const ThoughtsView({super.key});

  @override
  ThoughtsViewState createState() => ThoughtsViewState();
}

class ThoughtsViewState extends State<ThoughtsView> {
  int _currentRating = 1;

  int get currentRating => _currentRating;

  String _getRatingString(int rating) {
    switch (rating) {
      case 0: return 'bad';
      case 1: return 'good';
      case 2: return 'fire';
      default: return 'good';
    }
  }

  @override
  void initState() {
    super.initState();
    final firestoreProvider = Provider.of<FirestoreProvider>(context, listen: false);
    firestoreProvider.addListener(_updateRatingFromLatestThought);
  }

  @override
  void dispose() {
    final firestoreProvider = Provider.of<FirestoreProvider>(context, listen: false);
    firestoreProvider.removeListener(_updateRatingFromLatestThought);
    super.dispose();
  }

  void _updateRatingFromLatestThought() {
    final firestoreProvider = Provider.of<FirestoreProvider>(context, listen: false);
    
    if (firestoreProvider.currentTrackThoughts.isNotEmpty) {
      final latestThought = firestoreProvider.currentTrackThoughts.first;
      final ratingMap = {
        'bad': 0,
        'good': 1,
        'fire': 2
      };
      
      setState(() {
        _currentRating = ratingMap[latestThought['rating']] ?? 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Ratings(
            initialRating: _getRatingString(_currentRating),
            onRatingChanged: (rating) {
              setState(() {
                _currentRating = rating;
                print('Current rating: $_currentRating');
              });
            },
          ),
          const SizedBox(height: 16),
          const NotesDisplay(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}