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
  String _getRatingString(int rating) {
    switch (rating) {
      case 0:
        return 'bad';
      case 2:
        return 'fire';
      default:
        return 'good';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Consumer<FirestoreProvider>(
            builder: (context, firestoreProvider, child) {
              print("Current rating in FirestoreProvider: ${firestoreProvider.currentRating}");
              return Ratings(
                initialRating: firestoreProvider.currentRating,
                onRatingChanged: (rating) {
                  String ratingString = _getRatingString(rating);
                  setState(() {
                    firestoreProvider.setRating(ratingString);
                  });
                },
              );
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