import 'package:flutter/material.dart';
import 'pages/nowplaying.dart';
//import 'pages/search.dart';
//临时把search页面注释掉，监视 login 页面
import 'pages/roam.dart';
import 'pages/login.dart';
import 'test_widget/test_spotify.dart';
import 'package:provider/provider.dart';
import 'providers/spotify_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => SpotifyProvider(),
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MyApp(),
      ),
    ),
  );
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
    const NowPlaying(),
    TestSpotify(),
    //const Search(),
    //临时把search页面注释掉，监视 login 页面
    const Roam(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.music_note),
            SizedBox(width: 8),
            Text('Spotoolfy')
          ],
        ),
        actions: [
          IconButton.filledTonal(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                constraints: const BoxConstraints(
                  minWidth: 400,
                ),
                builder: (BuildContext context) {
                  return const Login();
                },
              );
            },
            icon: const Icon(Icons.person_outlined),
          ),
          const SizedBox(width: 8,),
        ],
      ),
      body: _pages[_selectedIndex],
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
    );
  }
}