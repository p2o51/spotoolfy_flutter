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
  static const Duration _reconnectDelay = Duration(seconds: 2);
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

  /// 检查是否已认证
  Future<bool> isAuthenticated() async {
    try {
      final token = await _secureStorage.read(key: _accessTokenKey);
      final expirationStr = await _secureStorage.read(key: _expirationKey);

      if (token == null || expirationStr == null) {
        print('未找到保存的令牌或过期时间');
        return false;
      }

      final expiration = DateTime.parse(expirationStr);
      // 如果令牌即将过期（比如还有5分钟就过期），也尝试刷新
      if (expiration.subtract(const Duration(minutes: 5)).isBefore(DateTime.now())) {
        print('令牌即将过期，尝试刷新');
        return await refreshToken() != null;
      }

      print('找到有效的访问令牌');
      return true;
    } catch (e) {
      print('检查认证状态失败: $e');
      return false;
    }
  }

  /// 监听连接状态
  void _setupConnectionListener() {
    try {
      // 先取消之前的监听
      _connectionSubscription?.cancel();
      
      if (!_connectionMonitoringEnabled) {
        print('连接监控已禁用，不设置监听器');
        return;
      }
      
      _connectionSubscription = SpotifySdk.subscribeConnectionStatus().listen(
        (status) async {
          if (!status.connected && !_isReconnecting) {
            // 检查是否在短时间内多次断开连接
            final now = DateTime.now();
            if (_lastDisconnectionTime != null && 
                now.difference(_lastDisconnectionTime!) < _disconnectionThreshold) {
              print('短时间内检测到多次断开，暂时忽略...');
              return;
            }
            
            print('检测到连接断开，开始重连流程...');
            _lastDisconnectionTime = now;
            await _handleDisconnection();
          }
        },
        onError: (e) {
          print('连接状态监听错误: $e');
          _handleDisconnection();
        },
      );
      print('已设置Spotify连接状态监听器');
    } catch (e) {
      print('设置连接监听器失败: $e');
    }
  }
  
  // 禁用连接监控
  void disableConnectionMonitoring() {
    _connectionMonitoringEnabled = false;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    print('已禁用Spotify连接监控');
  }
  
  // 启用连接监控
  void enableConnectionMonitoring() {
    _connectionMonitoringEnabled = true;
    _setupConnectionListener();
    print('已启用Spotify连接监控');
  }

  Future<String?> login({List<String>? scopes}) async {
    try {
      print('开始登录流程...');
      
      // 先检查是否已经认证
      print('开始自动登录检查...');
      if (await isAuthenticated()) {
        print('已有有效令牌，无需重新登录');
        final token = await _secureStorage.read(key: _accessTokenKey);
        
        // 确保 Remote 已连接
        try {
          final connected = await SpotifySdk.connectToSpotifyRemote(
            clientId: clientId,
            redirectUrl: redirectUrl,
            accessToken: token,
          );
          
          if (connected) {
            print('使用现有令牌连接到 Spotify Remote 成功');
            // 设置连接状态监听
            _setupConnectionListener();
          } else {
            print('使用现有令牌连接到 Spotify Remote 失败，但令牌仍有效');
          }
        } catch (e) {
          print('使用现有令牌连接到 Spotify Remote 时出错: $e');
        }
        
        return token;
      } else {
        print('未找到有效的认证信息，需要重新登录');
      }
      
      // 实际登录逻辑
      print('尝试获取访问令牌...');
      try {
        // 使用SpotifySdk获取访问令牌
        final accessToken = await SpotifySdk.getAccessToken(
          clientId: clientId,
          redirectUrl: redirectUrl,
          scope: (scopes ?? defaultScopes).join(','),
        );
        
        if (accessToken.isNotEmpty) {
          print('成功获取访问令牌');
          
          // 设置过期时间并保存
          final expirationDateTime = DateTime.now().add(const Duration(hours: 1));
          await _saveAuthResponse(accessToken, expirationDateTime);
          
          // 连接到Spotify Remote
          print('尝试连接到Spotify Remote...');
          
          bool connected = false;
          try {
            connected = await SpotifySdk.connectToSpotifyRemote(
              clientId: clientId,
              redirectUrl: redirectUrl,
              accessToken: accessToken,
            );
          } catch (e) {
            print('连接到Spotify Remote失败: $e');
            print('将尝试再次连接...');
            
            // 等待一下再重试一次
            await Future.delayed(const Duration(seconds: 2));
            try {
              connected = await SpotifySdk.connectToSpotifyRemote(
                clientId: clientId,
                redirectUrl: redirectUrl,
                accessToken: accessToken,
              );
            } catch (retryError) {
              print('第二次连接到Spotify Remote也失败: $retryError');
            }
          }
          
          if (connected) {
            print('成功连接到 Spotify Remote');
            // 设置连接状态监听
            _setupConnectionListener();
          } else {
            print('无法连接到 Spotify Remote，但令牌获取成功');
          }
          
          return accessToken;
        } else {
          print('获取访问令牌失败: 返回空令牌');
          throw SpotifyAuthException('登录失败：获取的访问令牌为空');
        }
      } catch (e) {
        print('获取访问令牌失败: $e');
        throw SpotifyAuthException('登录失败：无法获取访问令牌', code: '401');
      }
    } catch (e, stack) {
      print('Spotify 登录错误详情:');
      print('错误类型: ${e.runtimeType}');
      print('错误消息: $e');
      print('堆栈跟踪:');
      print(stack);
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
      print('检测到短时间内多次重连尝试，暂停重连30秒...');
      await Future.delayed(Duration(seconds: 30));
      _reconnectAttempts = 0;
    }
    
    // 开始重连流程
    await _reconnect();
  }

  // 改进的重连逻辑
  Future<void> _reconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('达到最大重连次数，停止重连');
      _isReconnecting = false;
      return;
    }

    try {
      print('尝试重连 (${_reconnectAttempts + 1}/$_maxReconnectAttempts)...');
      
      // 先检查是否真的需要重连
      try {
        // 尝试发送一个简单的API请求，检查连接是否实际可用
        final headers = await getAuthenticatedHeaders();
        final response = await http.get(
          Uri.parse('https://api.spotify.com/v1/me'),
          headers: headers,
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          print('API连接实际上是可用的，跳过不必要的重连');
          _isReconnecting = false;
          _reconnectAttempts = 0;
          return;
        }
      } catch (e) {
        // 请求失败或超时，确实需要重连
        print('确认API连接不可用: $e');
      }
      
      // 保存当前活跃设备ID
      String? activeDeviceId;
      try {
        final playbackState = await getPlaybackState();
        activeDeviceId = playbackState['device']?['id'];
        print('当前活跃设备ID: $activeDeviceId');
      } catch (e) {
        print('获取当前设备失败: $e');
      }
      
      // 先尝试刷新令牌
      final newToken = await refreshToken();
      if (newToken == null) {
        print('刷新令牌失败，无法重连');
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
        print('重连成功');
        // 成功连接后暂停一下，让连接稳定
        await Future.delayed(const Duration(seconds: 1));
        
        _isReconnecting = false;
        _reconnectAttempts = 0;
        
        // 如果有活跃设备，重新将播放切回该设备
        if (activeDeviceId != null) {
          print('正在恢复到原设备: $activeDeviceId');
          try {
            // 先验证设备是否仍然可用
            final devices = await getAvailableDevices();
            final deviceExists = devices.any((d) => d['id'] == activeDeviceId);
            
            if (deviceExists) {
              await transferPlayback(activeDeviceId, play: true);
              print('成功恢复到原设备');
            } else {
              print('原设备不再可用，无法恢复');
            }
          } catch (e) {
            print('恢复到原设备失败: $e');
          }
        }
        return;
      }

      // 如果重连失败，增加重试次数并延迟后重试
      _reconnectAttempts++;
      if (_reconnectAttempts < _maxReconnectAttempts) {
        final delay = Duration(seconds: 2 * _reconnectAttempts); // 指数退避
        print('重连失败，${delay.inSeconds}秒后重试...');
        _reconnectTimer = Timer(delay, _reconnect);
      } else {
        print('达到最大重连次数，停止重连');
        _isReconnecting = false;
      }
    } catch (e) {
      print('重连过程出错: $e');
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
      print('开始刷新访问令牌...');
      
      // 1. 直接尝试获取新的访问令牌
      final accessToken = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: defaultScopes.join(','),
      );

      print('成功获取新的访问令牌');

      // 2. 设置新的过期时间并保存
      final expirationDateTime = DateTime.now().add(const Duration(hours: 1));
      await _saveAuthResponse(accessToken, expirationDateTime);

      // 3. 尝试连接Remote（可选的）
      try {
        final connected = await SpotifySdk.connectToSpotifyRemote(
          clientId: clientId,
          redirectUrl: redirectUrl,
        );
        if (connected) {
          print('刷新令牌后成功连接到 Spotify Remote');
        } else {
          print('刷新令牌后无法连接到 Spotify Remote，但不影响基本功能');
        }
      } catch (e) {
        print('刷新令牌后连接 Remote 失败: $e');
        print('继续使用基本功能...');
      }

      return accessToken;
    } catch (e) {
      print('刷新访问令牌失败: $e');
      // 如果刷新失败，清除存储的令牌
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
      print('成功保存认证信息');
    } catch (e) {
      print('保存认证信息失败: $e');
      rethrow;
    }
  }

  /// 获取当前的访问令牌，如果即将过期会自动刷新
  Future<String?> getAccessToken() async {
    try {
      if (!await isAuthenticated()) return null;
      
      final token = await _secureStorage.read(key: _accessTokenKey);
      final expirationStr = await _secureStorage.read(key: _expirationKey);
      
      if (token == null || expirationStr == null) return null;
      
      final expiration = DateTime.parse(expirationStr);
      // 如果令牌即将过期（还有5分钟），尝试刷新
      if (expiration.subtract(const Duration(minutes: 5)).isBefore(DateTime.now())) {
        return await refreshToken();
      }
      
      return token;
    } catch (e) {
      print('获取访问令牌失败: $e');
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
      print('获取用户信息失败: $e');
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
      print('获取当前播放曲目时出错: $e');
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
      print('获取播放状态时出错: $e');
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
            print('检测到设备发生变化，恢复到原设备: $currentDeviceId');
            await transferPlayback(currentDeviceId, play: !isPlaying);  // 保持原来的播放状态
          }
        } catch (e) {
          print('检查设备变化或恢复设备失败: $e');
        }
      }
    } catch (e) {
      print('播放/暂停切换时出错: $e');
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
        print('获取当前设备失败: $e');
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
            print('检测到设备发生变化，恢复到原设备: $currentDeviceId');
            await transferPlayback(currentDeviceId, play: true);
          }
        } catch (e) {
          print('检查设备变化或恢复设备失败: $e');
        }
      }
    } catch (e) {
      print('跳转下一首时出错: $e');
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
        print('获取当前设备失败: $e');
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
            print('检测到设备发生变化，恢复到原设备: $currentDeviceId');
            await transferPlayback(currentDeviceId, play: true);
          }
        } catch (e) {
          print('检查设备变化或恢复设备失败: $e');
        }
      }
    } catch (e) {
      print('跳转上一首时出错: $e');
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
      print('检查歌曲保存状态时出错: $e');
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
      print('保存歌曲时出错: $e');
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
      print('移除歌曲时出错: $e');
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
      print('切换歌曲保存状态时出错: $e');
      rethrow;
    }
  }

  Future<void> refreshAccessToken(String refreshToken) async {
    try {
      final result = await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUrl,
          serviceConfiguration: _serviceConfiguration,
          refreshToken: refreshToken,
          grantType: 'refresh_token',
        ),
      );
      
      var accessToken = result.accessToken;
      
    } catch (e) {
      print('刷新 token 失败: $e');
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
      print('获取播放队列时出错: $e');
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
      print('设置循环模式时出错: $e');
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
      print('设置随机播放时出错: $e');
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
      print('获取最近播放记录时出错: $e');
      rethrow;
    }
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
      print('获取播放列表详情时出错: $e');
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
      print('获取专辑详情时出错: $e');
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
        print('获取当前设备失败: $e');
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
            print('检测到设备发生变化，恢复到原设备: $currentDeviceId');
            await transferPlayback(currentDeviceId, play: true);
          }
        } catch (e) {
          print('检查设备变化或恢复设备失败: $e');
        }
      }
    } catch (e) {
      print('跳转播放位置时出错: $e');
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
      print('获取可用设备时出错: $e');
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
      print('转移播放时出错: $e');
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
      print('开始播放时出错: $e');
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
      print('开始播放时出错: $e');
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
      print('在上下文中播放歌曲时出错: $e');
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
      print('设置音量时出错: $e');
      rethrow;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    print('正在清理Spotify服务资源...');
    
    // 取消连接监听
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    // 取消重连定时器
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    // 重置状态
    _isReconnecting = false;
    _reconnectAttempts = 0;
    
    try {
      // 尝试断开与Spotify的连接
      await SpotifySdk.disconnect();
      print('已断开与Spotify的连接');
    } catch (e) {
      print('断开Spotify连接时出错: $e');
    }
  }
}