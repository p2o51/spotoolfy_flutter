//spotify_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:flutter/widgets.dart';

/// Spotify 认证响应模型
class SpotifyAuthResponse {
  final String accessToken;
  final String? refreshToken;
  final DateTime expirationDateTime;
  final String tokenType;

  SpotifyAuthResponse({
    required this.accessToken,
    this.refreshToken,
    required this.expirationDateTime,
    required this.tokenType,
  });
}

/// Spotify API 错误
class SpotifyAuthException implements Exception {
  final String message;
  final String? code;

  SpotifyAuthException(this.message, {this.code});

  @override
  String toString() => 'SpotifyAuthException: $message${code != null ? ' (code: $code)' : ''}';
}

/// Spotify 认证服务类
class SpotifyAuthService {
  final FlutterSecureStorage _secureStorage;

  // Spotify OAuth 配置
  final String clientId;
  final String redirectUrl;

  // 存储键名
  static const String _accessTokenKey = 'spotify_access_token';
  static const String _expirationKey = 'spotify_token_expiration';

  // 连接监听器变量
  StreamSubscription? _connectionSubscription;
  bool _connectionMonitoringEnabled = true;

  // Add WidgetsBinding instance
  late final WidgetsBinding _binding = WidgetsBinding.instance;

  SpotifyAuthService({
    required this.clientId,
    required this.redirectUrl,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    // Call registerLifecycle in the constructor
    _registerLifecycle();
  }

  // Add registerLifecycle method
  void _registerLifecycle() {
    _binding.addObserver(_AppLifecycleObserver(onResume: () async {
      final token = await getAccessToken();        // 仍有效就重连
      if (token != null) {
        try {
          await SpotifySdk.connectToSpotifyRemote(
            clientId: clientId,
            redirectUrl: redirectUrl,
            accessToken: token,
          );
        } catch (_) {/* 忽略失败 */}
      }
    }));
  }

  /// 获取默认的 scope 列表
  List<String> get defaultScopes => [
    'user-read-private',
    'user-read-email',
    'playlist-read-private',
    'user-library-read',
    'user-library-modify',
    'user-read-currently-playing',
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-recently-played',
  ];

  /// 通用的 API GET 请求方法
  Future<Map<String, dynamic>> apiGet(String endpoint) async {
    try {
      final token = await getAccessToken();
      if (token == null) {
        throw SpotifyAuthException('未认证或授权已过期', code: '401');
      }

      final uri = Uri.parse('https://api.spotify.com/v1$endpoint');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw SpotifyAuthException('授权已过期或无效', code: '401');
      } else {
        throw SpotifyAuthException(
          '请求失败：${response.statusCode}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API GET 请求失败: $e');
    }
  }

  /// 通用的 API PUT 请求方法
  Future<Map<String, dynamic>?> apiPut(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final token = await getAccessToken();
      if (token == null) {
        throw SpotifyAuthException('未认证或授权已过期', code: '401');
      }

      final uri = Uri.parse('https://api.spotify.com/v1$endpoint');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.statusCode == 204 || response.body.isEmpty) {
          return null;
        }
        try {
          return jsonDecode(response.body);
        } catch (e) {
          return null;
        }
      } else if (response.statusCode == 401) {
        throw SpotifyAuthException('授权已过期或无效', code: '401');
      } else {
        throw SpotifyAuthException(
          '请求失败：${response.statusCode}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API PUT 请求失败: $e');
    }
  }

  /// 检查是否已认证
  Future<bool> isAuthenticated() async {
    try {
      final token = await _secureStorage.read(key: _accessTokenKey);
      final expirationStr = await _secureStorage.read(key: _expirationKey);

      if (token == null || expirationStr == null) {
        return false;
      }

      final expiration = DateTime.parse(expirationStr);
      if (expiration.isBefore(DateTime.now())) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 监听连接状态
  void _setupConnectionListener() {
    try {
      _connectionSubscription?.cancel();
      
      if (!_connectionMonitoringEnabled) {
        return;
      }
      
      _connectionSubscription = SpotifySdk.subscribeConnectionStatus().listen(
        (status) async {
          if (!status.connected) {
            // 可以选择性地打印日志或设置内部状态，但不自动处理
            // --- 添加重连逻辑 ---
            // print('Spotify disconnected, attempting reconnect...'); // Add logging
            final token = await getAccessToken(); // Uses the updated getAccessToken with silent refresh
            if (token != null) {
              try {
                await SpotifySdk.connectToSpotifyRemote(
                  clientId: clientId,
                  redirectUrl: redirectUrl,
                  accessToken: token,
                );
                // print('Spotify reconnect attempt successful.'); // Add logging
              } catch (_) {
                 // print('Spotify reconnect attempt failed or already connecting.'); // Add logging
                 /* 忽略：可能正在连接 */
              }
            }
            // --- 重连逻辑结束 ---
          } else {
            // 连接成功时可以考虑触发一个回调或事件，如果需要的话
          }
        },
        onError: (e) {
          // 出错时也不再调用 _handleDisconnection()
        },
      );
    } catch (e) {
      // print('Error setting up Spotify SDK connection listener: $e');
    }
  }
  
  // 禁用连接监控
  void disableConnectionMonitoring() {
    _connectionMonitoringEnabled = false;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
  }
  
  // 启用连接监控
  void enableConnectionMonitoring() {
    _connectionMonitoringEnabled = true;
    _setupConnectionListener();
  }

  Future<String?> login({List<String>? scopes}) async {
    try {
      // 1. 检查是否已认证 (使用简化后的 isAuthenticated)
      if (await isAuthenticated()) {
        final token = await _secureStorage.read(key: _accessTokenKey);

        // 尝试连接 Spotify Remote。SDK 应处理重复连接。
        try {
          // 不再需要检查 isConnected 或 getConnectionStatus
          final connected = await SpotifySdk.connectToSpotifyRemote(
            clientId: clientId,
            redirectUrl: redirectUrl,
            accessToken: token, // SDK 需要 token 来连接 Remote
          );
          // 无论 connect 返回 true/false，都确保 listener 在运行
          if (_connectionSubscription == null || _connectionSubscription!.isPaused) {
              _setupConnectionListener();
          }
        } catch (e) {
          // Ignored: 连接错误可能是因为它已连接。确保监听器运行。
           if (_connectionSubscription == null || _connectionSubscription!.isPaused){
              _setupConnectionListener();
           }
          // print('Error connecting to Spotify Remote on existing auth: $e');
        }
        return token;
      }

      // 2. 如果未认证，执行 SpotifySdk 登录流程
      final scopeStr = (scopes ?? defaultScopes).join(',');
      try {
        final accessToken = await SpotifySdk.getAccessToken(
          clientId: clientId,
          redirectUrl: redirectUrl,
          scope: scopeStr,
        );

        if (accessToken.isNotEmpty) {
          // Spotify SDK 默认 token 有效期为 1 小时
          final expirationDateTime = DateTime.now().add(const Duration(hours: 1));
          // 使用修改后的 _saveAuthResponse
          await _saveAuthResponse(accessToken, expirationDateTime);

          // 登录成功后尝试连接 Spotify Remote
          try {
            final connected = await SpotifySdk.connectToSpotifyRemote(
              clientId: clientId,
              redirectUrl: redirectUrl,
              accessToken: accessToken,
            );
             // 无论 connect 返回 true/false，都确保 listener 在运行
             if (_connectionSubscription == null || _connectionSubscription!.isPaused) {
                 _setupConnectionListener();
             }
          } catch (e) {
             // Ignored: 连接错误可能是因为它已连接。确保监听器运行。
             if (_connectionSubscription == null || _connectionSubscription!.isPaused){
                _setupConnectionListener();
             }
            // print('Error connecting to Spotify Remote after login: $e');
            // 即使连接失败，登录本身也算成功，返回 token
          }

          return accessToken;
        } else {
          throw SpotifyAuthException('登录失败：获取的访问令牌为空');
        }
      } catch (sdkError) {
        // 细化错误处理
        if (sdkError.toString().contains('USER_CANCELLED') || // Android
            sdkError.toString().contains('cancelled') || // iOS
            sdkError.toString().contains('Auth flow cancelled by user')) { // General
          throw SpotifyAuthException('登录被用户取消', code: 'AUTH_CANCELLED');
        } else if (sdkError.toString().contains('CONFIG_ERROR') ||
                   sdkError.toString().contains('Could not find config')) {
           throw SpotifyAuthException('登录失败：Spotify SDK 配置错误，请检查 AndroidManifest/Info.plist', code: 'CONFIG_ERROR'); // 修正引号
        } else if (sdkError.toString().contains('Could not authenticate client')) {
           throw SpotifyAuthException('登录失败：无效的 Client ID 或 Redirect URI', code: 'AUTH_FAILED'); // 修正引号
        }
        // 其他 PlatformException 或未知错误
        throw SpotifyAuthException('登录时发生未知错误: $sdkError', code: 'UNKNOWN_SDK_ERROR'); // 修正引号
      }
    } catch (e) {
      // 重新抛出已知的 SpotifyAuthException 或包装其他异常
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('登录失败: $e', code: 'LOGIN_FAILED'); // 修正引号
    }
  }

  /// 保存认证响应到安全存储
  Future<void> _saveAuthResponse(String accessToken, DateTime expirationDateTime) async {
    try {
      await Future.wait([
        _secureStorage.write(key: _accessTokenKey, value: accessToken),
        _secureStorage.write(
          key: _expirationKey,
          value: expirationDateTime.toIso8601String(),
        ),
      ]);
    } catch (e) {
      // print('Error saving auth response to secure storage: $e');
      rethrow;
    }
  }

  /// 如果本地 token 过期 → 尝试静默拿一枚新 token；
  /// 若失败则返回 null（让上层决定是否 logout）
  Future<String?> getAccessToken() async {
    final token = await _secureStorage.read(key: _accessTokenKey);
    final expStr = await _secureStorage.read(key: _expirationKey);

    if (token == null || expStr == null) return null;

    final exp = DateTime.parse(expStr);
    if (exp.isAfter(DateTime.now())) return token;        // 仍有效

    // ---------- 已过期，静默续期 ----------
    // Add logging here if needed
    // print('Spotify token expired, attempting silent refresh...'); 
    try {
      final newToken = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: defaultScopes.join(','),
      );

      if (newToken.isNotEmpty) {
        // print('Silent refresh successful.'); // Add logging
        await _saveAuthResponse(
          newToken,
          DateTime.now().add(const Duration(hours: 1)),
        );
        return newToken;
      }
    } catch (_) {
      // print('Silent refresh failed.'); // Add logging
      /* 静默失败，交由上层处理 */
    }
    return null;
  }

  /// 登出并清除所有存储的令牌
  Future<void> logout() async {
    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _expirationKey),
    ]);
    try {
      await SpotifySdk.disconnect();
    } catch (e) {
      // Ignored: Failure during disconnect is not critical
    }
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
  }

  /// 创建带有认证头的 HTTP 请求头
  Future<Map<String, String>> getAuthenticatedHeaders() async {
    final token = await getAccessToken();
    if (token == null) {
      throw SpotifyAuthException('未认证或授权已过期', code: '401');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }
  /// 获取用户信息
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取用户信息失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('获取用户信息时出错: $e');
    }
  }

  /// 获取当前正在播放的曲目
  Future<Map<String, dynamic>?> getCurrentlyPlayingTrack() async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: headers,
      );

      // 如果返回204表示当前没有播放内容
      if (response.statusCode == 204) {
        return null;
      }

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取当前播放曲目失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('获取当前播放曲目时出错: $e');
    }
  }

  /// 获取播放状态
  Future<Map<String, dynamic>> getPlaybackState() async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player'),
        headers: headers,
      );

      // 如果返回204表示当前没有活动设备
      if (response.statusCode == 204) {
        return {};
      }

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取播放状态失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      rethrow;
    }
  }

  /// 播放/暂停切换
  Future<void> togglePlayPause() async {
    try {
      final playbackState = await getPlaybackState();
      final isPlaying = playbackState['is_playing'] ?? false;
      final currentDeviceId = playbackState['device']?['id'];
      
      final headers = await getAuthenticatedHeaders();
      
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/${isPlaying ? 'pause' : 'play'}'),
        headers: headers,
      );

      if (response.statusCode != 200 && 
          response.statusCode != 202 && 
          response.statusCode != 204) {
        throw SpotifyAuthException(
          '${isPlaying ? '暂停' : '播放'}失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
      
      // 确保设备没有变化，如果变化了，切回原设备
      if (currentDeviceId != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          final newPlaybackState = await getPlaybackState();
          final newDeviceId = newPlaybackState['device']?['id'];
          if (newDeviceId != currentDeviceId) {
            await transferPlayback(currentDeviceId, play: !isPlaying);  // 保持原来的播放状态
          }
        } catch (e) {
          // Ignored: Failure to re-transfer playback is acceptable.
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 下一首
  Future<void> skipToNext() async {
    try {
      // 获取当前设备信息
      String? currentDeviceId;
      try {
        final playbackState = await getPlaybackState();
        currentDeviceId = playbackState['device']?['id'];
      } catch (e) {
        // Ignored: Failure to get current device is not critical for seek
      }
      
      final headers = await getAuthenticatedHeaders();
      final response = await http.post(
        Uri.parse('https://api.spotify.com/v1/me/player/next'),
        headers: headers,
      );

      if (response.statusCode != 200 && 
          response.statusCode != 202 && 
          response.statusCode != 204) {
        throw SpotifyAuthException(
          '跳转下一首失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
      
      // 确保设备没有变化，如果变化了，切回原设备
      if (currentDeviceId != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          final newPlaybackState = await getPlaybackState();
          final newDeviceId = newPlaybackState['device']?['id'];
          if (newDeviceId != currentDeviceId) {
            await transferPlayback(currentDeviceId, play: true);
          }
        } catch (e) {
          // Ignored: Failure to re-transfer playback is acceptable.
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 上一首
  Future<void> skipToPrevious() async {
    try {
      // 获取当前设备信息
      String? currentDeviceId;
      try {
        final playbackState = await getPlaybackState();
        currentDeviceId = playbackState['device']?['id'];
      } catch (e) {
        // Ignored: Failure to get current device is not critical for seek
      }
      
      final headers = await getAuthenticatedHeaders();
      final response = await http.post(
        Uri.parse('https://api.spotify.com/v1/me/player/previous'),
        headers: headers,
      );

      if (response.statusCode != 200 && 
          response.statusCode != 202 && 
          response.statusCode != 204) {
        throw SpotifyAuthException(
          '跳转上一首失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
      
      // 确保设备没有变化，如果变化了，切回原设备
      if (currentDeviceId != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          final newPlaybackState = await getPlaybackState();
          final newDeviceId = newPlaybackState['device']?['id'];
          if (newDeviceId != currentDeviceId) {
            await transferPlayback(currentDeviceId, play: true);
          }
        } catch (e) {
          // Ignored: Failure to re-transfer playback is acceptable.
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 检查歌曲是否已保存到用户的音乐库
  Future<bool> isTrackSaved(String trackId) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/tracks/contains?ids=$trackId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '检查歌曲保存状态失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      final List<dynamic> results = json.decode(response.body);
      return results.isNotEmpty ? results[0] : false;
    } catch (e) {
      rethrow;
    }
  }

  /// 将歌曲保存到用户的音乐库
  Future<void> saveTrack(String trackId) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/tracks'),
        headers: headers,
        body: json.encode({'ids': [trackId]}),
      );

      if (response.statusCode != 200 && 
          response.statusCode != 201) {
        throw SpotifyAuthException(
          '保存歌曲败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 从用户的音乐库中移除歌曲
  Future<void> removeTrack(String trackId) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.delete(
        Uri.parse('https://api.spotify.com/v1/me/tracks'),
        headers: headers,
        body: json.encode({'ids': [trackId]}),
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '移除歌曲失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 切换歌曲的保存状态
  Future<bool> toggleTrackSave(String trackId) async {
    try {
      final isSaved = await isTrackSaved(trackId);
      if (isSaved) {
        await removeTrack(trackId);
        return false;
      } else {
        await saveTrack(trackId);
        return true;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取播放队列
  Future<Map<String, dynamic>> getPlaybackQueue() async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/queue'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取播放队列失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      rethrow;
    }
  }

  /// 设置循环模式
  /// mode: "track" - 单曲循环, "context" - 列表循环, "off" - 关闭循环
  Future<void> setRepeatMode(String mode) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/repeat?state=$mode'),
        headers: headers,
      );

      if (response.statusCode != 200 && 
          response.statusCode != 202 && 
          response.statusCode != 204) {
        throw SpotifyAuthException(
          '设置循环模式失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 设置随机播放状态
  Future<void> setShuffle(bool state) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/shuffle?state=$state'),
        headers: headers,
      );

      if (response.statusCode != 200 && 
          response.statusCode != 202 && 
          response.statusCode != 204) {
        throw SpotifyAuthException(
          '设置随机播放失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取最近播放记录
  Future<Map<String, dynamic>> getRecentlyPlayed({int limit = 50}) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/recently-played?limit=$limit'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取最近播放记录失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches the raw recently played track items from Spotify API.
  Future<List<Map<String, dynamic>>> getRecentlyPlayedRawTracks({int limit = 50}) async {
    final response = await apiGet('/me/player/recently-played?limit=$limit');
    // Return the list of items directly, or empty list if null
    return List<Map<String, dynamic>>.from(response['items'] ?? []);
  }

  /// 获取播放列表详情
  Future<Map<String, dynamic>> getPlaylist(String playlistId) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/playlists/$playlistId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取播放列表详情失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      rethrow;
    }
  }

  /// 获取专辑详情
  Future<Map<String, dynamic>> getAlbum(String albumId) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取专辑详情失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> seekToPosition(Duration position) async {
    try {
      // 获取当前设备信息
      String? currentDeviceId;
      try {
        final playbackState = await getPlaybackState();
        currentDeviceId = playbackState['device']?['id'];
      } catch (e) {
        // Ignored: Failure to get current device is not critical for seek
      }
      
      final headers = await getAuthenticatedHeaders();
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/seek?position_ms=${position.inMilliseconds}'),
        headers: headers,
      );

      if (response.statusCode != 200 && 
          response.statusCode != 202 && 
          response.statusCode != 204) {
        throw SpotifyAuthException(
          '跳转播放位置失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
      
      // 确保设备没有变化，如果变化了，切回原设备
      if (currentDeviceId != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          final newPlaybackState = await getPlaybackState();
          final newDeviceId = newPlaybackState['device']?['id'];
          if (newDeviceId != currentDeviceId) {
            await transferPlayback(currentDeviceId, play: true);
          }
        } catch (e) {
          // Ignored: Failure to re-transfer playback is acceptable.
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取可用设备列表
  Future<List<Map<String, dynamic>>> getAvailableDevices() async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/devices'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          '获取可用设备失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['devices']);
    } catch (e) {
      rethrow;
    }
  }

  /// 转移播放到指定设备
  Future<void> transferPlayback(String deviceId, {bool play = false}) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player'),
        headers: headers,
        body: json.encode({
          'device_ids': [deviceId],
          'play': play,
        }),
      );

      if (response.statusCode != 202 && response.statusCode != 204) {
        throw SpotifyAuthException(
          '转移播放失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 开始播放专辑或播放列表
  Future<void> playContext({
    required String contextUri,
    int? offsetIndex,
    String? deviceId,
  }) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final body = {
        'context_uri': contextUri,
        if (offsetIndex != null) 'offset': {'position': offsetIndex},
      };

      final queryParams = deviceId != null ? '?device_id=$deviceId' : '';
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 202 && response.statusCode != 204) {
        throw SpotifyAuthException(
          '开始播放失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 播放单曲
  Future<void> playTrack({
    required String trackUri,
    String? deviceId,
  }) async {
    try {
      final headers = await getAuthenticatedHeaders();
      final body = {
        'uris': [trackUri],
      };

      final queryParams = deviceId != null ? '?device_id=$deviceId' : '';
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 202 && response.statusCode != 204) {
        throw SpotifyAuthException(
          '开始播放失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 在上下文中播放特定歌曲
  Future<void> playTrackInContext({
    required String contextUri,
    required String trackUri,
    String? deviceId,
  }) async {
    try {
      final headers = await getAuthenticatedHeaders();
      
      // 首先检查设备状态
      if (deviceId != null) {
        final devicesResponse = await http.get(
          Uri.parse('https://api.spotify.com/v1/me/player/devices'),
          headers: headers,
        );
        
        if (devicesResponse.statusCode == 200) {
          final devices = json.decode(devicesResponse.body)['devices'] as List;
          final targetDevice = devices.firstWhere(
            (d) => d['id'] == deviceId,
            orElse: () => null,
          );
          
          if (targetDevice != null && targetDevice['is_restricted'] == true) {
            throw SpotifyAuthException(
              '此设备（${targetDevice['name']}）不支持通过 API 控制播放。\n'
              '请使用 Spotify 或设备自带的应用进行控制。',
              code: 'RESTRICTED_DEVICE',
            );
          }
        }
      }
      
      // 对于非受限设备，使用标准播放方式
      final trackResponse = await http.get(
        Uri.parse('https://api.spotify.com/v1/tracks/${trackUri.split(':').last}'),
        headers: headers,
      );

      if (trackResponse.statusCode != 200) {
        throw SpotifyAuthException(
          '获取歌曲信息失败: ${trackResponse.body}',
          code: trackResponse.statusCode.toString(),
        );
      }

      final trackInfo = json.decode(trackResponse.body);
      
      // 构建播放请求
      Map<String, dynamic> body = {
        'context_uri': contextUri,
      };

      // 尝试使用 URI 作为 offset
      body['offset'] = {'uri': trackUri};

      final queryParams = deviceId != null ? '?device_id=$deviceId' : '';
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 202 && response.statusCode != 204) {
        // 如果使用 URI 失败，尝试使用 track_number
        final trackNumber = trackInfo['track_number'];
        if (response.statusCode == 404 && trackNumber is int && trackNumber > 0) {
          body['offset'] = {'position': trackNumber - 1};
          
          final retryResponse = await http.put(
            Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
            headers: headers,
            body: json.encode(body),
          );
          
          if (retryResponse.statusCode != 202 && retryResponse.statusCode != 204) {
            throw SpotifyAuthException(
              '开始播放失败: ${retryResponse.body}',
              code: retryResponse.statusCode.toString(),
            );
          }
        } else {
          throw SpotifyAuthException(
            '开始播放失败: ${response.body}',
            code: response.statusCode.toString(),
          );
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 设置播放音量
  Future<void> setVolume(int volumePercent, {String? deviceId}) async {
    try {
      final headers = await getAuthenticatedHeaders();
      
      // 构建查询参数
      final queryParams = {
        'volume_percent': volumePercent.toString(),
        if (deviceId != null) 'device_id': deviceId,
      };
      
      final uri = Uri.https(
        'api.spotify.com',
        '/v1/me/player/volume',
        queryParams,
      );
      
      final response = await http.put(uri, headers: headers);

      if (response.statusCode != 202 && response.statusCode != 204) {
        throw SpotifyAuthException(
          '设置音量失败: ${response.body}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    try {
      await SpotifySdk.disconnect();
    } catch (e) {
      // Ignored: Failure during disconnect is not critical
    }
  }

  /// Search for items on Spotify
  Future<Map<String, dynamic>> search(String query, List<String> types, {int limit = 20, int offset = 0, String? market}) async {
    if (query.trim().isEmpty) {
      throw SpotifyAuthException('Search query cannot be empty.');
    }
    
    final typesParam = types.join(',');
    final encodedQuery = Uri.encodeComponent(query);
    String endpoint = '/search?q=$encodedQuery&type=$typesParam&limit=$limit&offset=$offset';
    if (market != null) {
      endpoint += '&market=$market';
    }
    
    return await apiGet(endpoint);
  }
}

// Add helper class at the end of the file
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Future<void> Function() onResume;
  _AppLifecycleObserver({required this.onResume});
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();           // 回到前台主动重连
    }
  }
}