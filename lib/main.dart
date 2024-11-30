import 'package:flutter/material.dart';
import 'pages/nowplaying.dart';
import 'pages/search.dart';
import 'pages/roam.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}


class _MyAppState extends State<MyApp> {
  int _selectedIndex = 0;
  
  // 准备所有页面
  final List<Widget> _pages = [
    NowPlaying(),
    Search(),
    Roam(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotoolfy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(Icons.music_note),
              SizedBox(width: 8),
              Text('Spotoolfy')
            ],
          ),
          actions: [
            IconButton.filledTonal(onPressed: (){}, icon: Icon(Icons.person_outlined),),
            SizedBox(width: 8,),
          ],

        ),
        body: _pages[_selectedIndex], // 直接切换页面
        bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.music_note),
            label: 'NowPlaying',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio),
            label: 'Roam',
          ),
        ],
        ),
      ),
    );
  }
}