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

      if (token == null || expirationStr == null) return false;

      final expiration = DateTime.parse(expirationStr);
      if (expiration.isBefore(DateTime.now())) {
        return await refreshToken() != null;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> login({List<String>? scopes}) async {
    try {
      print('准备连接到 Spotify...');
      print('配置信息:');
      print('- clientId: $clientId');
      print('- redirectUrl: $redirectUrl');
      print('- scopes: ${scopes ?? defaultScopes}');

      final String accessToken = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: (scopes ?? defaultScopes).join(','),
      );

      print('连接成功，获取到访问令牌');

      final expirationDateTime = DateTime.now().add(const Duration(hours: 1));

      print('开始保存访问令牌...');
      await _saveAuthResponse(accessToken, expirationDateTime);
      print('访问令牌保存完成');

      return accessToken;
    } catch (e, stack) {
      print('连接 Spotify 错误详情:');
      print('错误类型: ${e.runtimeType}');
      print('错误消息: $e');
      print('堆栈跟踪:');
      print(stack);
      rethrow;
    }
  }

  /// 刷新访问令牌
  Future<String?> refreshToken() async {
    try {
      final storedRefreshToken = await _secureStorage.read(key: _refreshTokenKey);

      // Spotify SDK 没有直接的刷新令牌方法，需要重新获取
      final accessToken = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: defaultScopes.join(','),
      );

      final expirationDateTime = DateTime.now().add(const Duration(hours: 1));

      await _saveAuthResponse(accessToken, expirationDateTime);
      return accessToken;
    } catch (e) {
      // 如果刷新失败，清除存储的令牌
      await logout();
      return null;
    }
  }

  /// 保存认证响应到安全存储
  Future<void> _saveAuthResponse(String accessToken, DateTime expirationDateTime) async {
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      _secureStorage.write(
        key: _expirationKey,
        value: expirationDateTime.toIso8601String(),
      ),
    ]);
  }

  /// 获取当前的访问令牌
  Future<String?> getAccessToken() async {
    if (!await isAuthenticated()) return null;
    return await _secureStorage.read(key: _accessTokenKey);
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
    } catch (e) {
      print('播放/暂停切换时出错: $e');
      rethrow;
    }
  }

  /// 下一首
  Future<void> skipToNext() async {
    try {
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
    } catch (e) {
      print('跳转下一首时出错: $e');
      rethrow;
    }
  }

  /// 上一首
  Future<void> skipToPrevious() async {
    try {
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
}