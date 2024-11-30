import 'package:flutter/material.dart';
import 'package:spotoolfy_flutter/widgets/materialui.dart';
class NotesDisplay extends StatefulWidget {
  const NotesDisplay({super.key});

  @override
  State<NotesDisplay> createState() => _NotesDisplayState();
}

class _NotesDisplayState extends State<NotesDisplay> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconHeader(icon: Icons.comment_bank_outlined, text: 'RECORDS'),
          ListDemo(),
        ],
      ),
    );
  }
}

class ListDemo extends StatelessWidget {
  const ListDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          leading: CircleAvatar(child: Text('今')),
          title: Text('\"Kisses from my muses, Truses for the bruises.\"', style: TextStyle(fontSize: 16, height: 0.95),),
          subtitle: Text('Note'),
        ),
        Divider(height: 0),
        ListTile(
          leading: CircleAvatar(child: Text('13')),
          title: Text.rich(TextSpan(
            children: [
              TextSpan(text: 'Changed from ', style: TextStyle(fontSize: 16),),
              WidgetSpan(child: Icon(Icons.sentiment_neutral_rounded, size: 20), alignment: PlaceholderAlignment.middle,),
              TextSpan(text: ' to ', style: TextStyle(fontSize: 16),),
              WidgetSpan(child: Icon(Icons.whatshot_outlined, size: 20), alignment: PlaceholderAlignment.middle,),  
            ],
          )),
          subtitle: Text('Rating'),
        ),
        Divider(height: 0),
        ListTile(
          leading: CircleAvatar(child: Text('初')),
          title: Text('\"I feel like I\'m soaked in water, in Miami.\"', style: TextStyle(fontSize: 16, height: 0.95),),
          subtitle: Text('Note'),
        ),
        Divider(height: 0),
        
      ],
    );
  }
}