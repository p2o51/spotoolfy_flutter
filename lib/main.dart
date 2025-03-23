import 'package:flutter/material.dart';
import 'pages/nowplaying.dart';
import 'pages/search.dart';
import 'pages/roam.dart';
import 'pages/login.dart';
import 'pages/devices.dart';
import 'package:provider/provider.dart';
import 'providers/spotify_provider.dart';
import 'providers/auth_provider.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/firestore_provider.dart';
import 'package:flutter/services.dart';
import 'providers/theme_provider.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  final spotifyProvider = SpotifyProvider();
  // 尝试自动登录
  await spotifyProvider.autoLogin();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: spotifyProvider),
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
      navigatorKey: navigatorKey,
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

class ProgressIndicator extends StatefulWidget {
  final double progress;
  final double duration;
  final bool isPlaying;

  const ProgressIndicator({
    super.key,
    required this.progress,
    required this.duration,
    required this.isPlaying,
  });

  @override
  State<ProgressIndicator> createState() => _ProgressIndicatorState();
}

class _ProgressIndicatorState extends State<ProgressIndicator> with SingleTickerProviderStateMixin {
  late double _currentProgress;
  Timer? _progressTimer;
  late final AnimationController _animationController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _currentProgress = widget.progress;
    
    _progressAnimation = Tween<double>(
      begin: _currentProgress,
      end: _currentProgress,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _startProgressTimer();
  }

  @override
  void didUpdateWidget(ProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果进度差异大于1秒，使用动画过渡
    if ((widget.progress - _currentProgress).abs() > 1000) {
      _progressAnimation = Tween<double>(
        begin: _currentProgress,
        end: widget.progress,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ));
      _currentProgress = widget.progress;
      _animationController.forward(from: 0);
    }
    // 播放状态改变时更新计时器
    if (widget.isPlaying != oldWidget.isPlaying) {
      _startProgressTimer();
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    if (widget.isPlaying) {
      _progressTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
        if (mounted) {
          setState(() {
            _currentProgress = math.min(_currentProgress + 1000, widget.duration);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        final displayProgress = _animationController.isAnimating 
            ? _progressAnimation.value 
            : _currentProgress;
            
        return LinearProgressIndicator(
          value: displayProgress / widget.duration,
          minHeight: 4.0,
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 当应用从后台恢复时，刷新播放状态
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      spotifyProvider.refreshCurrentTrack();
    }
  }
  
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
        title: Row(
          children: [
            Image.asset(
              'assets/icons/adaptive_icon_monochrome.png',
              width: 40,  // 设置合适的宽度
              height: 40, // 设置合适的高度
              color: Theme.of(context).colorScheme.onSurface, // 使图标颜色与主题匹配
            ),
            const SizedBox(width: 8),
            const Text('Spotoolfy')
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
                  return const DevicesPage();
                },
              );
            },
            icon: const Icon(Icons.devices),
          ),
          const SizedBox(width: 8),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: Consumer<SpotifyProvider>(
            builder: (context, provider, child) {
              final currentTrack = provider.currentTrack;
              if (currentTrack == null || currentTrack['item'] == null) {
                return const SizedBox.shrink();
              }
              
              final progress = currentTrack['progress_ms'] ?? 0;
              final duration = currentTrack['item']['duration_ms'] ?? 1;
              final isPlaying = currentTrack['is_playing'] ?? false;
              
              return ProgressIndicator(
                progress: progress.toDouble(),
                duration: duration.toDouble(),
                isPlaying: isPlaying,
              );
            },
          ),
        ),
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
      bottomNavigationBar: isLargeScreen ? null : SafeArea(
        bottom: false,
        child: NavigationBar(
          height: Platform.isIOS ? 55 : null,  // 只在 iOS 平台设置固定高度
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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