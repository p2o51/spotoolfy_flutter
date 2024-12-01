//spotify_service.dart
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  }) : _appAuth = appAuth ?? FlutterAppAuth(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// 配置服务端点
  AuthorizationServiceConfiguration get _serviceConfiguration =>
      const AuthorizationServiceConfiguration(
        authorizationEndpoint: _authEndpoint,
        tokenEndpoint: _tokenEndpoint,
      );

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

Future<SpotifyAuthResponse> login({List<String>? scopes}) async {
  try {
    print('准备 OAuth 请求...');
    print('配置信息:');
    print('- clientId: $clientId');
    print('- clientSecret: ${clientSecret.substring(0, 4)}...');
    print('- redirectUrl: $redirectUrl');
    print('- scopes: ${scopes ?? defaultScopes}');
    print('- authEndpoint: $_authEndpoint');
    print('- tokenEndpoint: $_tokenEndpoint');

    final request = AuthorizationTokenRequest(
      clientId,
      redirectUrl,
      clientSecret: clientSecret,
      serviceConfiguration: _serviceConfiguration,
      scopes: scopes ?? defaultScopes,
      promptValues: ['login'],
      additionalParameters: {
        'show_dialog': 'true',
        'response_type': 'code',
        'access_type': 'offline',
      },
    );

    print('创建授权请求对象成功，准备发送请求...');
    
    // 使用分步授权方式
    final authResult = await _appAuth.authorize(
      AuthorizationRequest(
        clientId,
        redirectUrl,
        serviceConfiguration: _serviceConfiguration,
        scopes: scopes ?? defaultScopes,
        promptValues: ['login'],
        additionalParameters: {
          'show_dialog': 'true',
        },
      ),
    );

    print('收到授权响应');
    if (authResult == null) {
      print('授权失败: 收到空响应');
      throw SpotifyAuthException('Authorization failed: No response received');
    }

    print('授权成功，开始获取令牌...');

    // 使用授权码获取令牌
    final tokenResult = await _appAuth.token(
      TokenRequest(
        clientId,
        redirectUrl,
        authorizationCode: authResult.authorizationCode,
        codeVerifier: authResult.codeVerifier,
        serviceConfiguration: _serviceConfiguration,
        clientSecret: clientSecret,
      ),
    );

    if (tokenResult == null) {
      throw SpotifyAuthException('Token exchange failed: No response received');
    }

    final response = SpotifyAuthResponse(
      accessToken: tokenResult.accessToken!,
      refreshToken: tokenResult.refreshToken,
      expirationDateTime: tokenResult.accessTokenExpirationDateTime ??
          DateTime.now().add(const Duration(hours: 1)),
      tokenType: tokenResult.tokenType ?? 'Bearer',
    );

    print('开始保存认证响应...');
    await _saveAuthResponse(response);
    print('认证响应保存完成');
    
    return response;
  } catch (e, stack) {
    print('OAuth 错误详情:');
    print('错误类型: ${e.runtimeType}');
    print('错误消息: $e');
    print('堆栈跟踪:');
    print(stack);
    rethrow;
    }
  }

  /// 刷新访问令牌
  Future<SpotifyAuthResponse?> refreshToken() async {
    try {
      final storedRefreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (storedRefreshToken == null) {
        throw SpotifyAuthException('No refresh token available');
      }

      final result = await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUrl,
          serviceConfiguration: _serviceConfiguration,
          refreshToken: storedRefreshToken,
          grantType: 'refresh_token',
        ),
      );

      if (result == null) {
        throw SpotifyAuthException('Token refresh failed: No response received');
      }

      final response = SpotifyAuthResponse(
        accessToken: result.accessToken!,
        refreshToken: result.refreshToken ?? storedRefreshToken,
        expirationDateTime: result.accessTokenExpirationDateTime ??
            DateTime.now().add(const Duration(hours: 1)),
        tokenType: result.tokenType ?? 'Bearer',
      );

      await _saveAuthResponse(response);
      return response;
    } catch (e) {
      // 如果刷新失败，清除存储的令牌
      await logout();
      return null;
    }
  }

  /// 保存认证响应到安全存储
  Future<void> _saveAuthResponse(SpotifyAuthResponse response) async {
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: response.accessToken),
      if (response.refreshToken != null)
        _secureStorage.write(key: _refreshTokenKey, value: response.refreshToken),
      _secureStorage.write(
        key: _expirationKey,
        value: response.expirationDateTime.toIso8601String(),
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
          '保存歌曲失败: ${response.body}',
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

      if (result == null) throw Exception('Failed to refresh token');
      
      var accessToken = result.accessToken;
      
    } catch (e) {
      print('刷新 token 失败: $e');
      rethrow;
    }
  }
}