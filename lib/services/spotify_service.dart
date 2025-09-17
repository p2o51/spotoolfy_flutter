//spotify_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'dart:convert';
import 'dart:async';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:collection/collection.dart'; // Added import for firstWhereOrNull

final logger = Logger();

/// Spotify 认证响应模型
class SpotifyAuthResponse {
  final String accessToken;
  final DateTime expirationDateTime;
  final String tokenType;

  SpotifyAuthResponse({
    required this.accessToken,
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
  String toString() =>
      'SpotifyAuthException: $message${code != null ? ' (code: $code)' : ''}';
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

  // 添加自动重连开关
  bool _autoReconnectRemote = false;

  // 防止并发刷新导致循环或竞态
  bool _isRefreshingToken = false;

  /// Token 刷新回调
  void Function()? onTokenRefreshed;

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
    _appLifecycleObserver = _AppLifecycleObserver(onResume: () async {
      await ensureFreshToken(); // 只续 token
      if (_autoReconnectRemote) {
        _setupConnectionListener();
      }
    });
    _binding.addObserver(_appLifecycleObserver!); // Add observer
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
        'app-remote-control', // 添加 Spotify SDK 官方推荐的核心权限
      ];

  /// 简化版 _buildUri，放在类顶部工具区
  Uri _buildUri(String path, [Map<String, String>? query]) => Uri.https(
      'api.spotify.com', '/v1$path', query?.isEmpty ?? true ? null : query);

  /// 通用的网络重试包装器
  Future<T> _withNetworkRetry<T>(
    Future<T> Function() operation, {
    String operationName = 'API操作',
    int maxRetries = 3,
    Duration baseDelay = const Duration(milliseconds: 500),
  }) async {
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        return await operation().timeout(const Duration(seconds: 10));
      } catch (e) {
        retryCount++;

        // 如果是认证错误，不重试
        if (e is SpotifyAuthException) rethrow;

        // 如果是网络连接错误且还有重试次数，则重试
        final errorString = e.toString().toLowerCase();
        final isRetryableNetworkError =
            errorString.contains('socketexception') ||
                errorString.contains('timeoutexception') ||
                errorString.contains('connection') ||
                errorString.contains('clientexception');

        if (retryCount < maxRetries && isRetryableNetworkError) {
          logger.d('$operationName: 网络错误，尝试第 $retryCount 次重试: $e');
          await Future.delayed(baseDelay * retryCount); // 指数退避
          continue;
        }

        // 其他错误或重试次数用完
        if (isRetryableNetworkError) {
          // 重试耗尽的网络错误
          throw SpotifyAuthException(
              '$operationName 时出错: 网络连接失败，已尝试 $maxRetries 次',
              code: 'NETWORK_RETRY_EXHAUSTED');
        } else {
          // 其他非网络错误
          throw SpotifyAuthException('$operationName 时出错: $e',
              code: 'OPERATION_FAILED_UNKNOWN');
        }
      }
    }

    // 此处逻辑理论上不会到达，因为上面的循环会抛出异常或成功返回
    // 但为了完整性，保留一个最终的异常抛出
    throw SpotifyAuthException('$operationName 时出错: 未知错误，重试逻辑未按预期工作',
        code: 'RETRY_LOGIC_ERROR');
  }

  // 新增：创建认证请求头，可选是否包含 Content-Type
  Future<Map<String, String>> _authHeaders({bool hasBody = true}) async {
    final token = await ensureFreshToken();
    if (token == null) {
      throw SpotifyAuthException('未认证或授权已过期', code: '401');
    }
    return {
      'Authorization': 'Bearer $token',
      if (hasBody) 'Content-Type': 'application/json',
    };
  }

  /// 通用的 API GET 请求方法
  Future<Map<String, dynamic>> apiGet(String endpoint) async {
    try {
      final token =
          await getAccessToken(); // getAccessToken internally calls ensureFreshToken
      if (token == null) {
        throw SpotifyAuthException('未认证或授权已过期', code: '401');
      }

      final uri = Uri.parse('https://api.spotify.com/v1$endpoint');
      // For GET requests, Content-Type is generally not needed.
      // Using _authHeaders with hasBody = false, or a simpler header map directly.
      final headers = await _authHeaders(
          hasBody: false); // Or simply {'Authorization': 'Bearer $token'}

      final response = await http.get(
        uri,
        headers: headers,
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
  Future<Map<String, dynamic>?> apiPut(String endpoint,
      {Map<String, dynamic>? body}) async {
    try {
      final token = await getAccessToken();
      if (token == null) {
        throw SpotifyAuthException('未认证或授权已过期', code: '401');
      }

      final uri = Uri.parse('https://api.spotify.com/v1$endpoint');
      // Use _authHeaders, hasBody will be true if body is not null, false otherwise
      final headers = await _authHeaders(hasBody: body != null);

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
      final token = await _secureStorage
          .read(key: _accessTokenKey)
          .catchError((_) => null);
      final expirationStr = await _secureStorage
          .read(key: _expirationKey)
          .catchError((_) => null);

      if (token == null || expirationStr == null) {
        return false;
      }

      final expiration = DateTime.parse(expirationStr);
      if (expiration.isBefore(DateTime.now())) {
        return false;
      }

      return true;
    } catch (e) {
      logger.w('检查认证状态时出错，可能是Keystore未解锁: $e');
      return false;
    }
  }

  /// 监听连接状态
  void _setupConnectionListener() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      // Spotify SDK connect/subscribe might not be supported or behave differently on other platforms.
      return;
    }
    try {
      _connectionSubscription?.cancel();

      if (!_connectionMonitoringEnabled) {
        return;
      }

      _connectionSubscription = SpotifySdk.subscribeConnectionStatus().listen(
        (status) async {
          if (!status.connected) {
            final token = await ensureFreshToken();
            if (token != null) {
              try {
                await SpotifySdk.connectToSpotifyRemote(
                  clientId: clientId,
                  redirectUrl: redirectUrl,
                  accessToken: token,
                );
              } catch (_) {
                /* 忽略失败 */
              }
            }
          }
        },
        onError: (e) {
          // 出错时不再调用 _handleDisconnection()
        },
      );
    } catch (e) {
      // 忽略设置监听器时的错误
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

  /// 确保 token 有效，必要时刷新
  Future<String?> ensureFreshToken() async {
    try {
      final tok = await _secureStorage
          .read(key: _accessTokenKey)
          .catchError((_) => null);
      final expS = await _secureStorage
          .read(key: _expirationKey)
          .catchError((_) => null);
      if (tok != null && expS != null) {
        final exp = DateTime.parse(expS);
        if (exp.difference(DateTime.now()).inMinutes > 5) return tok;
      }
    } catch (e) {
      logger.w('读取token时出错，可能是Keystore未解锁: $e');
      return null;
    }

    if (_isRefreshingToken) {
      // 已有刷新流程在执行，避免重复调起SDK
      return null;
    }

    // —— token 不够用了，重新拿 ——
    try {
      _isRefreshingToken = true;
      final newTok = await SpotifySdk.getAccessToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        scope: defaultScopes.join(','),
      );
      if (newTok.isEmpty) {
        throw SpotifyAuthException('获取的访问令牌为空', code: 'AUTH_EMPTY_TOKEN');
      }

      // We don't get expiresIn directly from getAccessToken(),
      // so we'll use a slightly reduced fixed duration.
      await saveAuthResponse(newTok,
          expiresInSeconds: 55 * 60); // 55 minutes in seconds
      onTokenRefreshed?.call();
      return newTok;
    } catch (sdkError) {
      final errorString = sdkError.toString();

      if (errorString.contains('USER_CANCELLED') ||
          errorString.contains('cancelled') ||
          errorString.contains('Auth flow cancelled by user')) {
        throw SpotifyAuthException('授权被用户取消', code: 'AUTH_CANCELLED');
      }

      if (errorString.contains('socket') ||
          errorString.contains('timeout') ||
          errorString.contains('network') ||
          errorString.contains('connection')) {
        throw SpotifyAuthException('网络连接异常，无法刷新访问令牌',
            code: 'TOKEN_REFRESH_FAILED_NETWORK');
      }

      if (errorString.contains('CONFIG_ERROR') ||
          errorString.contains('Could not find config')) {
        throw SpotifyAuthException('Spotify SDK 配置错误: $sdkError',
            code: 'CONFIG_ERROR');
      }

      if (Platform.isIOS && errorString.contains('Connection attempt failed')) {
        throw SpotifyAuthException('iOS 连接 Spotify 失败，请重试',
            code: 'IOS_CONNECTION_FAILED');
      }

      throw SpotifyAuthException('刷新访问令牌失败: $sdkError',
          code: 'TOKEN_REFRESH_FAILED');
    } finally {
      _isRefreshingToken = false;
    }
  }

  /// 2. 需要 Remote 时再调
  Future<bool> connectRemoteIfNeeded() async {
    // 直接返回 true，暂时跳过 Remote 连接，专注于 Web API
    logger.d(
        'connectRemoteIfNeeded: Skipped, returning true directly for Web API testing.');
    return true;
    /*
    try {
      final status = await SpotifySdk.subscribeConnectionStatus().first;
      if (status.connected == true) return true;

      final tok = await ensureFreshToken();
      if (tok == null) return false; // 让上层弹登录

      final ok = await SpotifySdk.connectToSpotifyRemote(
        clientId: clientId,
        redirectUrl: redirectUrl,
        accessToken: tok,
      );
      if (ok) _setupConnectionListener();
      return ok;
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('连接 Remote 失败: $e');
    }
    */
  }

  // 修改 login 方法，移除自动连接 Remote 的逻辑
  Future<String?> login({List<String>? scopes}) async {
    try {
      // 1. 检查是否已认证，如果已经认证且 token 有效，则直接返回
      final existingToken = await ensureFreshToken();
      if (existingToken != null) {
        onTokenRefreshed?.call();
        return existingToken;
      }

      // 2. 如果未认证或 token 无效，执行 SpotifySdk 登录流程
      final scopeStr = (scopes ?? defaultScopes).join(',');
      try {
        final accessToken = await SpotifySdk.getAccessToken(
          clientId: clientId,
          redirectUrl: redirectUrl,
          scope: scopeStr,
        );

        if (accessToken.isNotEmpty) {
          // Use the same saving mechanism as ensureFreshToken
          await saveAuthResponse(accessToken,
              expiresInSeconds: 55 * 60); // 55 minutes
          onTokenRefreshed?.call(); // 登录成功后也通知
          return accessToken;
        } else {
          throw SpotifyAuthException('登录失败：获取的访问令牌为空');
        }
      } catch (sdkError) {
        final errorString = sdkError.toString();
        if (errorString.contains('USER_CANCELLED') ||
            errorString.contains('cancelled') ||
            errorString.contains('Auth flow cancelled by user')) {
          throw SpotifyAuthException('登录被用户取消', code: 'AUTH_CANCELLED');
        } else if (errorString.contains('CONFIG_ERROR') ||
            errorString.contains('Could not find config')) {
          throw SpotifyAuthException(
              '登录失败：Spotify SDK 配置错误，请检查 AndroidManifest/Info.plist',
              code: 'CONFIG_ERROR');
        } else if (errorString.contains('Could not authenticate client')) {
          throw SpotifyAuthException('登录失败：无效的 Client ID 或 Redirect URI',
              code: 'AUTH_FAILED');
        } else if (Platform.isIOS &&
            errorString.contains('Connection attempt failed')) {
          // iOS特有的连接失败处理
          logger.w('iOS登录时遇到连接失败，尝试重新配置: $errorString');
          throw SpotifyAuthException('iOS登录失败：请确保已安装Spotify应用并重试',
              code: 'IOS_CONNECTION_FAILED');
        }
        throw SpotifyAuthException('登录时发生未知错误: $sdkError',
            code: 'UNKNOWN_SDK_ERROR');
      }
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('登录失败: $e', code: 'LOGIN_FAILED');
    }
  }

  /// 保存认证响应到安全存储
  Future<void> saveAuthResponse(String accessToken,
      {int expiresInSeconds = 3600}) async {
    // Default to 1 hour if not specified
    try {
      await Future.wait([
        _secureStorage.write(key: _accessTokenKey, value: accessToken),
        _secureStorage.write(
          key: _expirationKey,
          value: DateTime.now()
              .add(Duration(seconds: expiresInSeconds))
              .toIso8601String(),
        ),
      ]);
    } catch (e) {
      // logger.d('Error saving auth response to secure storage: $e');
      rethrow;
    }
  }

  /// 如果本地 token 过期 → 尝试静默拿一枚新 token；
  /// 若失败则返回 null（让上层决定是否 logout）
  Future<String?> getAccessToken() => ensureFreshToken();

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
    final token = await ensureFreshToken();
    if (token == null) {
      throw SpotifyAuthException('未认证或授权已过期', code: '401');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type':
          'application/json', // Keep for general use, specific calls might override
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
    return await _withNetworkRetry<Map<String, dynamic>?>(
      () async {
        final headers =
            await _authHeaders(hasBody: false); // GET request, no body
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
      },
      operationName: '获取当前播放曲目',
    );
  }

  /// 获取播放状态
  Future<Map<String, dynamic>> getPlaybackState() async {
    return await _withNetworkRetry<Map<String, dynamic>>(
      () async {
        final headers =
            await _authHeaders(hasBody: false); // GET request, no body
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
      },
      operationName: '获取播放状态',
    );
  }

  /// 创建辅助方法处理API请求，先不带device_id，失败时再补充
  Future<void> _withDevice(String path,
      {String method = 'PUT',
      Map<String, String> query = const {},
      Map<String, dynamic>? body}) async {
    logger.d("===== SPOTIFY API DEBUG (_withDevice) =====");
    String attemptType = "Initial";

    try {
      Future<http.Response> makeRequest(String deviceIdQuerySuffix) async {
        final fullPath =
            deviceIdQuerySuffix.isEmpty ? path : '$path$deviceIdQuerySuffix';
        final currentUri = _buildUri(fullPath, query);
        // Note: _buildUri already incorporates query parameters passed to it.
        // If device_id is part of the `query` map, it will be included.
        // If deviceIdQuerySuffix is used for retry, `query` might need to be adjusted or suffix used carefully.
        // For simplicity, let's ensure device_id is primarily handled via the `query` map for retries.

        final headers = await _authHeaders(hasBody: body != null);
        logger.d("[$attemptType Attempt] $method ${currentUri.toString()}");
        if (body != null)
          logger.d("[$attemptType Attempt] Body: ${jsonEncode(body)}");
        logger.d("[$attemptType Attempt] Headers: $headers");

        if (method == 'POST') {
          return await http.post(currentUri,
              headers: headers, body: body != null ? jsonEncode(body) : null);
        } else {
          // Default to PUT
          return await http.put(currentUri,
              headers: headers, body: body != null ? jsonEncode(body) : null);
        }
      }

      // Initial attempt (potentially without device_id in query if not passed by caller)
      http.Response r = await makeRequest("");
      logger.d("[$attemptType Attempt] Response Status: ${r.statusCode}");
      if (r.body.isNotEmpty) {
        logger.d("[$attemptType Attempt] Response Body: ${r.body}");
      } else {
        logger.d("[$attemptType Attempt] Response Body: Empty");
      }

      // For control endpoints like play, pause, next, previous, seek,
      // a 200 OK might also indicate success if the API behaves unexpectedly (though 204/202 is typical).
      // Since functionality is reported as working with 200, let's include it as a success code here.
      bool isSuccessStatusCode =
          r.statusCode == 204 || r.statusCode == 202 || r.statusCode == 200;

      if (isSuccessStatusCode) {
        logger.d(
            "[$attemptType Attempt] Successfully processed ($method $path) with status ${r.statusCode}.");
        logger.d("===== SPOTIFY API DEBUG (_withDevice) END =====");
        return;
      }

      if (r.statusCode == 401) {
        logger.d("[$attemptType Attempt] Authorization expired (401).");
        logger.d("===== SPOTIFY API DEBUG (_withDevice) END =====");
        throw SpotifyAuthException('授权已过期或无效', code: '401');
      }

      // If initial attempt failed with other 4xx/5xx, try with device_id
      logger.d(
          "[$attemptType Attempt] Failed (${r.statusCode}). Trying to find active device for retry...");
      attemptType = "Retry";

      final devices = await getAvailableDevices();
      logger.d("[$attemptType] Found ${devices.length} devices.");
      for (final d in devices) {
        logger.d(
            "[$attemptType] Device: ${d['name']} (${d['id']}), Active: ${d['is_active']}");
      }

      final activeDevice =
          devices.firstWhereOrNull((d) => d['is_active'] == true);
      String? targetDeviceIdForRetry;

      if (activeDevice != null) {
        targetDeviceIdForRetry = activeDevice['id'] as String?;
        logger.d(
            "[$attemptType] Using active device: ${activeDevice['name']} ($targetDeviceIdForRetry)");
      } else if (devices.isNotEmpty) {
        targetDeviceIdForRetry = devices.first['id'] as String?;
        logger.d(
            "[$attemptType] No active device, using first available: ${devices.first['name']} ($targetDeviceIdForRetry)");
      } else {
        logger.d("[$attemptType] No devices available for retry.");
        logger.d("===== SPOTIFY API DEBUG (_withDevice) END =====");
        throw SpotifyAuthException('找不到可用播放设备 (重试也无设备)',
            code: 'NO_DEVICE_ON_RETRY');
      }

      if (targetDeviceIdForRetry != null) {
        // Create a new query map for retry, adding/overriding device_id
        final retryQuery = Map<String, String>.from(query);
        retryQuery['device_id'] = targetDeviceIdForRetry;

        // Make sure to use the original path, _buildUri will append query
        final retryUri = _buildUri(path, retryQuery);
        final headersForRetry = await _authHeaders(hasBody: body != null);

        logger.d("[$attemptType Attempt] $method ${retryUri.toString()}");
        if (body != null)
          logger.d("[$attemptType Attempt] Body: ${jsonEncode(body)}");
        logger.d("[$attemptType Attempt] Headers: $headersForRetry");

        if (method == 'POST') {
          r = await http.post(retryUri,
              headers: headersForRetry,
              body: body != null ? jsonEncode(body) : null);
        } else {
          // Default to PUT
          r = await http.put(retryUri,
              headers: headersForRetry,
              body: body != null ? jsonEncode(body) : null);
        }

        logger.d("[$attemptType Attempt] Response Status: ${r.statusCode}");
        if (r.body.isNotEmpty) {
          logger.d("[$attemptType Attempt] Response Body: ${r.body}");
        } else {
          logger.d("[$attemptType Attempt] Response Body: Empty");
        }

        // 重试时也要包含200作为成功状态码
        if (r.statusCode == 204 || r.statusCode == 202 || r.statusCode == 200) {
          logger.d(
              "[$attemptType Attempt] Successfully processed ($method $path) with status ${r.statusCode}.");
          logger.d("===== SPOTIFY API DEBUG (_withDevice) END =====");
          return;
        }
        logger.d(
            "[$attemptType Attempt] Failed (${r.statusCode}). Error response: ${r.body}");
        logger.d("===== SPOTIFY API DEBUG (_withDevice) END =====");
        throw SpotifyAuthException('控制失败 (重试后): ${r.body}',
            code: r.statusCode.toString());
      }
      // Should not be reached if targetDeviceIdForRetry was null due to earlier throw, but as a safeguard:
      logger.d(
          "[$attemptType] Retry attempt not made as no target device ID was found.");
      logger.d("===== SPOTIFY API DEBUG (_withDevice) END =====");
      throw SpotifyAuthException('重试尝试未进行，无目标设备ID',
          code: 'RETRY_NOT_ATTEMPTED');
    } catch (e) {
      logger.d("Error in _withDevice: $e");
      if (e is SpotifyAuthException) {
        logger.d("===== SPOTIFY API DEBUG (_withDevice) END (Exception) =====");
        rethrow;
      }
      logger.d(
          "===== SPOTIFY API DEBUG (_withDevice) END (Unknown Exception) =====");
      throw SpotifyAuthException('_withDevice 内部错误: $e');
    }
  }

  /// 播放/暂停切换
  Future<void> togglePlayPause() async {
    logger.d('===== TOGGLE PLAY/PAUSE SERVICE =====');
    try {
      logger.d('获取当前播放状态...');
      final playbackState = await getPlaybackState();
      final isPlaying = playbackState['is_playing'] ?? false;
      final currentDeviceId = playbackState['device']?['id'] as String?;

      logger.d('当前播放状态: ${isPlaying ? "播放中" : "已暂停"}, 设备ID: $currentDeviceId');

      final action = isPlaying ? 'pause' : 'play';
      logger.d('即将执行操作: $action');

      // 始终尝试传递 device_id (如果已知)
      await _withDevice(
        '/me/player/$action',
        query: currentDeviceId != null ? {'device_id': currentDeviceId} : {},
      );

      logger.d('操作执行成功');
      logger.d('===== TOGGLE PLAY/PAUSE SERVICE END =====');
    } catch (e) {
      logger.d('togglePlayPause 出错: $e');
      logger.d('===== TOGGLE PLAY/PAUSE SERVICE END =====');
      rethrow;
    }
  }

  /// 下一首
  Future<void> skipToNext() async {
    try {
      final playbackState = await getPlaybackState();
      final currentDeviceId = playbackState['device']?['id'] as String?;
      await _withDevice(
        '/me/player/next',
        method: 'POST',
        query: currentDeviceId != null ? {'device_id': currentDeviceId} : {},
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 上一首
  Future<void> skipToPrevious() async {
    try {
      final playbackState = await getPlaybackState();
      final currentDeviceId = playbackState['device']?['id'] as String?;
      await _withDevice(
        '/me/player/previous',
        method: 'POST',
        query: currentDeviceId != null ? {'device_id': currentDeviceId} : {},
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 跳转到指定播放位置
  Future<void> seekToPosition(Duration position) async {
    try {
      final playbackState = await getPlaybackState();
      final currentDeviceId = playbackState['device']?['id'] as String?;
      await _withDevice(
        '/me/player/seek',
        query: {
          'position_ms': position.inMilliseconds.toString(),
          if (currentDeviceId != null) 'device_id': currentDeviceId,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 检查歌曲是否已保存到用户的音乐库
  Future<bool> isTrackSaved(String trackId) async {
    try {
      final headers =
          await _authHeaders(hasBody: false); // GET request, no body
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
      final headers =
          await _authHeaders(hasBody: true); // PUT request with body
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/tracks'),
        headers: headers,
        body: json.encode({
          'ids': [trackId]
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
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
      final headers =
          await _authHeaders(hasBody: true); // DELETE request with body
      final response = await http.delete(
        Uri.parse('https://api.spotify.com/v1/me/tracks'),
        headers: headers,
        body: json.encode({
          'ids': [trackId]
        }),
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
      final headers =
          await _authHeaders(hasBody: false); // GET request, no body
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
      final headers = await _authHeaders(
          hasBody: false); // PUT request, no body (query param)
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
      final headers = await _authHeaders(
          hasBody: false); // PUT request, no body (query param)
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
      final headers =
          await _authHeaders(hasBody: false); // GET request, no body
      final response = await http.get(
        Uri.parse(
            'https://api.spotify.com/v1/me/player/recently-played?limit=$limit'),
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
  Future<List<Map<String, dynamic>>> getRecentlyPlayedRawTracks(
      {int limit = 50}) async {
    final response = await apiGet('/me/player/recently-played?limit=$limit');
    // Return the list of items directly, or empty list if null
    return List<Map<String, dynamic>>.from(response['items'] ?? []);
  }

  /// 获取播放列表详情
  Future<Map<String, dynamic>> getPlaylist(String playlistId) async {
    try {
      final headers =
          await _authHeaders(hasBody: false); // GET request, no body
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
      final headers =
          await _authHeaders(hasBody: false); // GET request, no body
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

  /// 获取可用设备列表
  Future<List<Map<String, dynamic>>> getAvailableDevices() async {
    try {
      final headers =
          await _authHeaders(hasBody: false); // GET request, no body
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
      final headers =
          await _authHeaders(hasBody: true); // PUT request with body
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
      final headers =
          await _authHeaders(hasBody: true); // PUT request with body
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
      final headers =
          await _authHeaders(hasBody: true); // PUT request with body
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
      // Headers for initial device check and track info GET requests (no body)
      final getHeaders = await _authHeaders(hasBody: false);

      // 首先检查设备状态
      if (deviceId != null) {
        final devicesResponse = await http.get(
          Uri.parse('https://api.spotify.com/v1/me/player/devices'),
          headers: getHeaders, // Use getHeaders
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
        Uri.parse(
            'https://api.spotify.com/v1/tracks/${trackUri.split(':').last}'),
        headers: getHeaders, // Use getHeaders
      );

      if (trackResponse.statusCode != 200) {
        throw SpotifyAuthException(
          '获取歌曲信息失败: ${trackResponse.body}',
          code: trackResponse.statusCode.toString(),
        );
      }

      final trackInfo = json.decode(trackResponse.body);

      // Headers for the PUT play request (has body)
      final playHeaders = await _authHeaders(hasBody: true);

      // 构建播放请求
      Map<String, dynamic> body = {
        'context_uri': contextUri,
      };

      // 尝试使用 URI 作为 offset
      body['offset'] = {'uri': trackUri};

      final queryParams = deviceId != null ? '?device_id=$deviceId' : '';
      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
        headers: playHeaders, // Use playHeaders
        body: json.encode(body),
      );

      if (response.statusCode != 202 && response.statusCode != 204) {
        // 如果使用 URI 失败，尝试使用 track_number
        final trackNumber = trackInfo['track_number'];
        if (response.statusCode == 404 &&
            trackNumber is int &&
            trackNumber > 0) {
          body['offset'] = {'position': trackNumber - 1};

          final retryResponse = await http.put(
            Uri.parse('https://api.spotify.com/v1/me/player/play$queryParams'),
            headers: playHeaders, // Use playHeaders
            body: json.encode(body),
          );

          if (retryResponse.statusCode != 202 &&
              retryResponse.statusCode != 204) {
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
      final headers = await _authHeaders(
          hasBody: false); // PUT request, no body (query params)

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
    if (_appLifecycleObserver != null) {
      _binding.removeObserver(_appLifecycleObserver!); // Remove observer
      _appLifecycleObserver = null;
    }

    try {
      await SpotifySdk.disconnect();
    } catch (e) {
      // Ignored: Failure during disconnect is not critical
    }
  }

  /// Search for items on Spotify
  Future<Map<String, dynamic>> search(String query, List<String> types,
      {int limit = 20, int offset = 0, String? market}) async {
    if (query.trim().isEmpty) {
      throw SpotifyAuthException('Search query cannot be empty.');
    }

    final typesParam = types
        .map((t) => t.toLowerCase().trim())
        .join(','); // Ensure lowercase and trim spaces
    final encodedQuery = Uri.encodeComponent(query);
    String endpoint =
        '/search?q=$encodedQuery&type=$typesParam&limit=$limit&offset=$offset';
    if (market != null) {
      endpoint += '&market=$market';
    }

    return await apiGet(endpoint);
  }

  void enableAutoReconnect() => _autoReconnectRemote = true;
  void disableAutoReconnect() => _autoReconnectRemote = false;
}

// Add helper class at the end of the file
// Need to store the observer instance to remove it later
_AppLifecycleObserver? _appLifecycleObserver;

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Future<void> Function() onResume;
  _AppLifecycleObserver({required this.onResume});
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume(); // 回到前台主动重连
    }
  }
}
