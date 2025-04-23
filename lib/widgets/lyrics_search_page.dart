import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/lyrics_service.dart';
import '../services/lyrics/lyric_provider.dart'; // 需要直接使用 SongMatch 和 LyricProvider 类
import '../services/lyrics/qq_provider.dart'; // 添加QQ音乐提供者导入
import '../services/lyrics/netease_provider.dart'; // 添加网易云音乐提供者导入
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/notification_service.dart';
import '../providers/local_database_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// 在页面中使用自己的数据结构表示搜索结果
class LyricsSearchResult {
  final SongMatch match;
  final LyricProvider provider;

  LyricsSearchResult({required this.match, required this.provider});
}

class LyricsSearchPage extends StatefulWidget {
  final String initialTrackTitle;
  final String initialArtistName;
  final String trackId; // 保存选择的歌词时需要trackId

  const LyricsSearchPage({
    super.key,
    required this.initialTrackTitle,
    required this.initialArtistName,
    required this.trackId,
  });

  @override
  State<LyricsSearchPage> createState() => _LyricsSearchPageState();
}

class _LyricsSearchPageState extends State<LyricsSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isFetchingLyric = false;
  // 使用我们自己定义的类型
  List<LyricsSearchResult> _searchResults = [];
  String _currentQuery = '';

  // 注入服务
  late LyricsService _lyricsService;
  late NotificationService _notificationService;
  late LocalDatabaseProvider _localDbProvider; // 需要用于保存手动选择的歌词

  @override
  void initState() {
    super.initState();
    _lyricsService = Provider.of<LyricsService>(context, listen: false);
    _notificationService = Provider.of<NotificationService>(context, listen: false);
    _localDbProvider = Provider.of<LocalDatabaseProvider>(context, listen: false);

    // 设置初始查询并执行第一次搜索
    _currentQuery = '${widget.initialTrackTitle} ${widget.initialArtistName}'.trim();
    _searchController.text = _currentQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
       if (!mounted) return;
       _performSearch(_currentQuery);
       // 首帧后请求焦点
       FocusScope.of(context).requestFocus(_searchFocusNode);
       // 选择全部文本方便替换
       _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (!mounted || query.trim().isEmpty) {
      // 如果查询为空，清除结果
      setState(() {
        _searchResults = [];
        _currentQuery = '';
        _isLoading = false;
      });
      return;
    }

    _searchFocusNode.unfocus(); // 隐藏键盘

    setState(() {
      _isLoading = true;
      _searchResults = [];
      _currentQuery = query.trim(); // 存储当前查询
    });

    try {
      // 分别从每个提供者搜索
      final results = <LyricsSearchResult>[];
      
      // 获取所有可用的歌词提供者 - 不直接访问私有成员
      // 手动创建提供者实例 (与LyricsService中相同的提供者)
      final providers = [
        QQProvider(),
        NetEaseProvider(),
      ];
      
      // 从每个提供者获取搜索结果
      for (final provider in providers) {
        try {
          final match = await provider.search(_currentQuery, '');
          if (match != null) {
            results.add(LyricsSearchResult(match: match, provider: provider));
            
            // 更新UI显示已找到的结果
            if (mounted) {
              setState(() {
                _searchResults = List.from(results);
              });
            }
          }
        } catch (e) {
          debugPrint('Provider ${provider.name} search error: $e');
          // 继续尝试其他提供者
        }
      }
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
        // 已经在循环中更新了 _searchResults，这里不需要再设置
      });
    } catch (e) {
      if (mounted) {
        _notificationService.showErrorSnackBar('搜索错误: ${e.toString()}');
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 使用我们自己定义的LyricsSearchResult类型
  Future<void> _selectResult(LyricsSearchResult result) async {
     if (!mounted || _isFetchingLyric) return;

     setState(() {
       _isFetchingLyric = true;
     });

     try {
       _notificationService.showSnackBar('正在获取歌词...');
       // 使用提供者获取歌词
       final rawLyric = await result.provider.fetchLyric(result.match.songId);

       if (!mounted) return;

       if (rawLyric != null && rawLyric.isNotEmpty) {
         final normalizedLyric = result.provider.normalizeLyric(rawLyric);

         // 保存到缓存
         await _cacheLyric(widget.trackId, normalizedLyric, result.provider.name);
         debugPrint("手动获取的歌词已缓存，曲目ID：${widget.trackId}，提供者：${result.provider.name}");

         // 返回获取的歌词
         Navigator.of(context).pop(normalizedLyric);
       } else {
         _notificationService.showErrorSnackBar('无法获取所选歌曲的歌词。');
       }
     } catch (e) {
        if (mounted) {
         _notificationService.showErrorSnackBar('获取歌词时出错: ${e.toString()}');
        }
     } finally {
       if (mounted) {
         setState(() {
           _isFetchingLyric = false;
         });
       }
     }
  }
  
  // 手动将歌词缓存到共享首选项
  Future<void> _cacheLyric(String trackId, String lyric, String providerName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'manual_lyrics_cache_' + trackId;
      
      // 使用 LyricCacheData 保存
      final cacheData = LyricCacheData(
        provider: providerName,
        lyric: lyric,
        timestamp: (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      );
      
      // 保存到缓存
      await prefs.setString(cacheKey, json.encode(cacheData.toJson()));
      
      // 同时保存到 LyricsService 使用的常规缓存位置
      // 不直接使用私有变量
      final regularCacheKey = 'lyrics_cache_' + trackId;
      await prefs.setString(regularCacheKey, json.encode(cacheData.toJson()));
    } catch (e) {
      debugPrint('缓存歌词失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索歌词'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: '输入歌曲名和歌手名搜索...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : (_searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchController.clear();
                              _performSearch('');
                              _searchFocusNode.requestFocus();
                            },
                          )
                        : null),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                 setState(() {});
              },
              onSubmitted: (value) {
                _performSearch(value);
              },
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 初始状态提示
          if (!_isLoading && _searchResults.isEmpty && _currentQuery.isEmpty)
             Center(
               child: Padding(
                 padding: const EdgeInsets.all(20.0),
                 child: Text(
                   '输入歌曲名和歌手名搜索歌词',
                   textAlign: TextAlign.center,
                   style: Theme.of(context).textTheme.titleMedium?.copyWith(
                     color: Theme.of(context).colorScheme.secondary,
                   ),
                 ),
               ),
             )
          // 显示搜索结果
          else if (_searchResults.isNotEmpty)
            ListView.builder(
              padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                final providerDisplayName = result.provider.name == 'qq'
                    ? 'QQ音乐'
                    : result.provider.name == 'netease'
                      ? '网易云音乐'
                      : result.provider.name;

                return ListTile(
                   leading: Chip(
                     label: Text(providerDisplayName),
                     backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
                     labelStyle: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSecondaryContainer),
                     padding: EdgeInsets.zero,
                     visualDensity: VisualDensity.compact,
                     labelPadding: const EdgeInsets.symmetric(horizontal: 6.0),
                   ),
                  title: Text(result.match.title),
                  subtitle: Text(result.match.artist),
                  onTap: () => _selectResult(result),
                  enabled: !_isFetchingLyric,
                );
              },
            )
          // 无结果状态
          else if (!_isLoading && _searchResults.isEmpty && _currentQuery.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    '没有找到与"$_currentQuery"相关的结果',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ),
          // 加载指示器
          if (_isLoading || _isFetchingLyric)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
} 