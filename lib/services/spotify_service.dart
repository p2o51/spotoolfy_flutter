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
}