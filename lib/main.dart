import 'package:flutter/material.dart';
import 'pages/nowplaying.dart';
import 'pages/search.dart';
import 'pages/roam.dart';
import 'pages/login.dart';
import 'package:provider/provider.dart';
import 'providers/spotify_provider.dart';
import 'providers/auth_provider.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/firestore_provider.dart';
import 'package:flutter/services.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SpotifyProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProxyProvider2<AuthProvider, SpotifyProvider, FirestoreProvider>(
          create: (context) => FirestoreProvider(
            context.read<AuthProvider>(),
            context.read<SpotifyProvider>(),
          ),
          update: (context, auth, spotify, previous) =>
              previous ?? FirestoreProvider(auth, spotify),
        ),
      ],
      child: const MyThemedApp(),
    ),
  );
}

class MyThemedApp extends StatelessWidget {
  const MyThemedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: context.watch<ThemeProvider>().colorScheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
      ),
      home: const MyApp(),
    );
  }
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
    const Search(),
    const Roam(),
  ];

  @override
  Widget build(BuildContext context) {
    // 检查屏幕宽度
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

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
          if (isLargeScreen) ...[
            IconButton(
              onPressed: () {
                // 添加更多的导航选项或信息
              },
              icon: const Icon(Icons.info_outline),
            ),
          ],
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
      body: Row(
        children: [
          if (isLargeScreen)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.music_note),
                  label: Text('NowPlaying'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.search),
                  label: Text('Search'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.radio),
                  label: Text('Roam'),
                ),
              ],
            ),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: isLargeScreen ? null : NavigationBar(
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