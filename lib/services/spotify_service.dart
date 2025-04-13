//spotify_service.dart
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:spotify_sdk/spotify_sdk.dart';

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
  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _secureStorage;

  // Spotify OAuth 配置
  final String clientId;
  final String clientSecret;
  final String redirectUrl;

  // 存储键名
  static const String _accessTokenKey = 'spotify_access_token';
  static const String _refreshTokenKey = 'spotify_refresh_token';
  static const String _expirationKey = 'spotify_token_expiration';

  // Spotify OAuth 端点
  static const String _authEndpoint = 'https://accounts.spotify.com/authorize';
  static const String _tokenEndpoint = 'https://accounts.spotify.com/api/token';

  // 添加重连相关的常量
  static const int _maxReconnectAttempts = 3;
  static const Duration _maxReconnectTimeout = Duration(seconds: 10);
  
  // 添加重连状态追踪
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // 添加防抖变量
  DateTime? _lastDisconnectionTime;
  static const Duration _disconnectionThreshold = Duration(seconds: 10);

  // 添加连接监听器变量
  StreamSubscription? _connectionSubscription;
  bool _connectionMonitoringEnabled = true;

  SpotifyAuthService({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUrl,
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? secureStorage,
  }) : _appAuth = appAuth ?? const FlutterAppAuth(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// 配置服务端点
  AuthorizationServiceConfiguration get _serviceConfiguration =>
      const AuthorizationServiceConfiguration(
        authorizationEndpoint: _authEndpoint,
        tokenEndpoint: _tokenEndpoint,
      );

  /// 获取默认的 scope 列表
  List<String> get defaultScopes => [
    'app-remote-control',
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
      final token = await _secureStorage.read(key: _accessTokenKey);
      if (token == null) {
        throw SpotifyAuthException('未找到访问令牌');
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
        // 令牌已过期，尝试刷新
        final newToken = await refreshToken();
        if (newToken != null) {
          // 使用新令牌重试请求
          return apiGet(endpoint);
        }
        throw SpotifyAuthException('授权已过期，无法刷新令牌');
      } else {
        throw SpotifyAuthException(
          '请求失败：${response.statusCode}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API请求失败: $e');
    }
  }

  /// 通用的 API PUT 请求方法
  Future<Map<String, dynamic>?> apiPut(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final token = await _secureStorage.read(key: _accessTokenKey);
      if (token == null) {
        throw SpotifyAuthException('未找到访问令牌');
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
        // 令牌已过期，尝试刷新
        final newToken = await refreshToken();
        if (newToken != null) {
          // 使用新令牌重试请求
          return apiPut(endpoint, body: body);
        }
        throw SpotifyAuthException('授权已过期，无法刷新令牌');
      } else {
        throw SpotifyAuthException(
          '请求失败：${response.statusCode}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API PUT请求失败: $e');
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
      // 如果令牌即将过期（比如还有5分钟就过期），也尝试刷新
      if (expiration.subtract(const Duration(minutes: 5)).isBefore(DateTime.now())) {
        return await refreshToken() != null;
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
          if (!status.connected && !_isReconnecting) {
            final now = DateTime.now();
            if (_lastDisconnectionTime != null && 
                now.difference(_lastDisconnectionTime!) < _disconnectionThreshold) {
              return;
            }
            
            _lastDisconnectionTime = now;
            await _handleDisconnection();
          }
        },
        onError: (e) {
          // Ignored: Error during subscription status listening.
          _handleDisconnection();
        },
      );
    } catch (e) {
      // Ignored: Error setting up connection listener.
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
      if (await isAuthenticated()) {
        final token = await _secureStorage.read(key: _accessTokenKey);
        
        // 确保 Remote 已连接
        try {
          final connected = await SpotifySdk.connectToSpotifyRemote(
            clientId: clientId,
            redirectUrl: redirectUrl,
            accessToken: token,
          );
          
          if (connected) {
            _setupConnectionListener();
          }
        } catch (e) {
          // Ignored: Initial connection attempt failure is acceptable here.
        }
        
        return token;
      } else {
      }
      
      // 实际登录逻辑
      try {
        // 使用SpotifySdk获取访问令牌
        final scopeStr = (scopes ?? defaultScopes).join(',');
        
        try {
          final accessToken = await SpotifySdk.getAccessToken(
            clientId: clientId,
            redirectUrl: redirectUrl,
            scope: scopeStr,
          );
          
          if (accessToken.isNotEmpty) {
            final expirationDateTime = DateTime.now().add(const Duration(hours: 1));
            await _saveAuthResponse(accessToken, expirationDateTime);
            
            bool connected = false;
            try {
              connected = await SpotifySdk.connectToSpotifyRemote(
                clientId: clientId,
                redirectUrl: redirectUrl,
                accessToken: accessToken,
              );
            } catch (e) {
              await Future.delayed(const Duration(seconds: 2));
              try {
                connected = await SpotifySdk.connectToSpotifyRemote(
                  clientId: clientId,
                  redirectUrl: redirectUrl,
                  accessToken: accessToken,
                );
              } catch (retryError) {
                if (retryError.toString().contains('401')) {
                  throw SpotifyAuthException('登录失败：API凭据无效或未获得授权', code: '401');
                }
              }
            }
            
            if (connected) {
              _setupConnectionListener();
            }
            
            return accessToken;
          } else {
            throw SpotifyAuthException('登录失败：获取的访问令牌为空');
          }
        } catch (sdkError) {
          if (sdkError.toString().contains('PlatformException')) {
            throw SpotifyAuthException('登录失败：Spotify SDK平台配置可能不正确，请检查包名和重定向URI设置', code: 'PLATFORM_ERROR');
          } else if (sdkError.toString().contains('auth_cancelled') || 
                    sdkError.toString().contains('cancelled')) {
            throw SpotifyAuthException('登录被用户取消', code: 'AUTH_CANCELLED');
          }
          
          rethrow;
        }
      } catch (e) {
        if (e is SpotifyAuthException) {
          rethrow;
        } else if (e.toString().contains('401') || 
            e.toString().contains('invalid_client') || 
            e.toString().toLowerCase().contains('unauthorized')) {
          throw SpotifyAuthException('登录失败：API凭据无效或未获得授权', code: '401');
        }
        
        throw SpotifyAuthException('登录失败：无法获取访问令牌', code: e.toString().contains('401') ? '401' : 'UNKNOWN');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 处理断开连接
  Future<void> _handleDisconnection() async {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    _reconnectAttempts = 0;
    
    // 取消之前的重连定时器
    _reconnectTimer?.cancel();
    
    // 检查重连次数是否过多，如果是则暂停一段时间
    final now = DateTime.now();
    if (_lastDisconnectionTime != null && 
        now.difference(_lastDisconnectionTime!) < Duration(minutes: 1) && 
        _reconnectAttempts > 5) {
      await Future.delayed(Duration(seconds: 30));
      _reconnectAttempts = 0;
    }
    
    // 开始重连流程
    await _reconnect();
  }

  // 改进的重连逻辑
  Future<void> _reconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _isReconnecting = false;
      return;
    }

    try {
      try {
        final headers = await getAuthenticatedHeaders();
        final response = await http.get(
          Uri.parse('https://api.spotify.com/v1/me'),
          headers: headers,
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          _isReconnecting = false;
          _reconnectAttempts = 0;
          return;
        }
      } catch (e) {
        // Ignored: Failure to get playback state is not critical for reconnect.
      }
      
      // 保存当前活跃设备ID
      String? activeDeviceId;
      try {
        final playbackState = await getPlaybackState();
        activeDeviceId = playbackState['device']?['id'];
      } catch (e) {
        // Ignored: Failure to get playback state is not critical for reconnect.
      }
      
      // 先尝试刷新令牌
      final newToken = await refreshToken();
      if (newToken == null) {
        _isReconnecting = false;
        return;
      }

      // 设置重连超时
      final timeoutFuture = Future.delayed(_maxReconnectTimeout);
      
      // 尝试重连
      final connected = await Future.any([
        SpotifySdk.connectToSpotifyRemote(
          clientId: clientId,
          redirectUrl: redirectUrl,
          accessToken: newToken,  // 显式传递刚刚刷新的令牌
        ),
        timeoutFuture,
      ]).then((result) => result is bool ? result : false);

      if (connected) {
        await Future.delayed(const Duration(seconds: 1));
        
        _isReconnecting = false;
        _reconnectAttempts = 0;
        
        // 如果有活跃设备，重新将播放切回该设备
        if (activeDeviceId != null) {
          try {
            final devices = await getAvailableDevices();
            final deviceExists = devices.any((d) => d['id'] == activeDeviceId);
            
            if (deviceExists) {
              await transferPlayback(activeDeviceId, play: true);
            }
          } catch (e) {
            // Ignored: Failure to re-transfer playback is acceptable.
          }
        }
        return;
      }

      // 如果重连失败，增加重试次数并延迟后重试
      _reconnectAttempts++;
      if (_reconnectAttempts < _maxReconnectAttempts) {
        final delay = Duration(seconds: 2 * _reconnectAttempts); // 指数退避
        _reconnectTimer = Timer(delay, _reconnect);
      } else {
        _isReconnecting = false;
      }
    } catch (e) {
      _reconnectAttempts++;
      if (_reconnectAttempts < _maxReconnectAttempts) {
        final delay = Duration(seconds: 2 * _reconnectAttempts); // 指数退避
        _reconnectTimer = Timer(delay, _reconnect);
      } else {
        _isReconnecting = false;
      }
    }
  }

  /// 刷新访问令牌
  Future<String?> refreshToken() async {
    try {
      final accessToken = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: defaultScopes.join(','),
      );

      final expirationDateTime = DateTime.now().add(const Duration(hours: 1));
      await _saveAuthResponse(accessToken, expirationDateTime);

      try {
        final connected = await SpotifySdk.connectToSpotifyRemote(
          clientId: clientId,
          redirectUrl: redirectUrl,
        );
        if (connected) {
          // Connection successful, no specific action needed here.
        }
      } catch (e) {
        // Ignored: Failure to connect to Spotify Remote after token refresh.
      }

      return accessToken;
    } catch (e) {
      await logout();
      return null;
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
      rethrow;
    }
  }

  /// 获取当前的访问令牌，如果即将过期会自动刷新
  Future<String?> getAccessToken() async {
    try {
      if (!await isAuthenticated()) {
        return null;
      }
      
      final token = await _secureStorage.read(key: _accessTokenKey);
      final expirationStr = await _secureStorage.read(key: _expirationKey);
      
      if (token == null || expirationStr == null) {
        return null;
      }
      
      final expiration = DateTime.parse(expirationStr);
      // 如果令牌即将过期（还有5分钟），尝试刷新
      if (expiration.subtract(const Duration(minutes: 5)).isBefore(DateTime.now())) {
        return await refreshToken();
      }
      
      return token;
    } catch (e) {
      return null;
    }
  }

  /// 登出并清除所有存储的令牌
  Future<void> logout() async {
    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _expirationKey),
    ]);
  }

  /// 创建带有认证头的 HTTP 请求头
  Future<Map<String, String>> getAuthenticatedHeaders() async {
    final token = await getAccessToken();
    if (token == null) {
      throw SpotifyAuthException('No access token available');
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
          'Failed to get user profile: ${response.body}',
          code: response.statusCode.toString(),
        );
      }

      return json.decode(response.body);
    } catch (e) {
      rethrow;
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
      rethrow;
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

  Future<void> refreshAccessToken(String refreshToken) async {
    try {
      await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUrl,
          serviceConfiguration: _serviceConfiguration,
          refreshToken: refreshToken,
          grantType: 'refresh_token',
        ),
      );
    } catch (e) {
      // Ignored: Failure to get current device is not critical for seek
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
    
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _isReconnecting = false;
    _reconnectAttempts = 0;
    
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