import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/lyrics/lyric_provider.dart'; 
import '../services/lyrics/qq_provider.dart'; 
import '../services/lyrics/lrclib_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';

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
  late NotificationService _notificationService;

  @override
  void initState() {
    super.initState();
    _notificationService = Provider.of<NotificationService>(context, listen: false);

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
        LRCLibProvider(),
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
        _notificationService.showErrorSnackBar('${AppLocalizations.of(context)!.operationFailed}: ${e.toString()}');
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

     // 在异步调用前捕获 Navigator
     final navigator = Navigator.of(context);

     setState(() {
       _isFetchingLyric = true;
     });

     try {
       _notificationService.showSnackBar(AppLocalizations.of(context)!.lyricsFetching);
       // 使用提供者获取歌词
       final rawLyric = await result.provider.fetchLyric(result.match.songId);

       if (!mounted) return;

       if (rawLyric != null) {
         final normalizedLyric = result.provider.normalizeLyric(rawLyric);

         if (normalizedLyric.isNotEmpty) {
           // 保存到缓存
           await _cacheLyric(widget.trackId, normalizedLyric, result.provider.name);
           debugPrint("手动获取的歌词已缓存，曲目ID：${widget.trackId}，提供者：${result.provider.name}");

           // 返回获取的歌词
           navigator.pop(normalizedLyric); // 使用捕获的 navigator
           return;
         }
       }

       if (mounted) {
          _notificationService.showErrorSnackBar(AppLocalizations.of(context)!.lyricsNotFoundForTrack);
       }
     } catch (e) {
        if (mounted) {
         _notificationService.showErrorSnackBar(AppLocalizations.of(context)!.lyricsFetchError(e.toString()));
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
      final cacheKey = 'manual_lyrics_cache_$trackId'; // 使用插值
      
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
      final regularCacheKey = 'lyrics_cache_$trackId'; // 使用插值
      await prefs.setString(regularCacheKey, json.encode(cacheData.toJson()));
    } catch (e) {
      debugPrint('缓存歌词失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.searchLyrics),
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
                hintText: AppLocalizations.of(context)!.searchHint,
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
                            tooltip: AppLocalizations.of(context)!.clearSearch,
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
                   AppLocalizations.of(context)!.searchHint,
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
                final providerDisplayName = _providerDisplayName(context, result.provider.name);

                return ListTile(
                  leading: Chip(
                    label: Text(providerDisplayName),
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withAlpha((0.7 * 255).round()),
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
                    AppLocalizations.of(context)!.noResultsFound,
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
                color: Theme.of(context).scaffoldBackgroundColor.withAlpha((0.5 * 255).round()),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _providerDisplayName(BuildContext context, String providerName) {
    final l10n = AppLocalizations.of(context)!;
    switch (providerName) {
      case 'qq':
        return l10n.providerQQMusic;
      case 'lrclib':
        return l10n.providerLRCLIB;
      case 'netease':
        return l10n.providerNetease;
      default:
        return providerName;
    }
  }
}
