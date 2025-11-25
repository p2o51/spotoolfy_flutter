import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, VoidCallback, defaultTargetPlatform, kIsWeb;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/spotify_service.dart';
import '../env.dart';

/// 认证管理器 - 负责 Spotify 认证相关操作
///
/// 职责:
/// - 管理用户登录/登出
/// - 处理 token 刷新
/// - 管理 Client ID
/// - CSRF 防护
class SpotifyAuthManager {
  final Logger logger;
  final VoidCallback notifyListeners;

  static const String _clientIdKey = 'spotify_client_id';

  // 认证状态
  String? username;
  bool isLoading = false;
  bool _isInitialized = false;
  bool _isBootstrapping = false;

  // 服务实例
  late SpotifyAuthService _spotifyService;
  Completer<void> _initDone = Completer<void>();

  // CSRF 防护
  String? _currentState;

  SpotifyAuthManager({
    required this.logger,
    required this.notifyListeners,
  });

  // Getters
  bool get isInitialized => _isInitialized;
  SpotifyAuthService get spotifyService => _spotifyService;

  /// 异步初始化 bootstrap 过程
  Future<void> bootstrap({
    required VoidCallback onTokenRefreshed,
  }) async {
    if (_isBootstrapping) {
      logger.w('Bootstrap已在进行中，跳过重复调用');
      return;
    }

    _isBootstrapping = true;
    try {
      // 使用SharedPreferences读取Client ID
      final sp = await SharedPreferences.getInstance();
      final storedClientId = sp.getString(_clientIdKey);

      logger.d('Bootstrap: 从SharedPreferences读取ClientID: ${storedClientId ?? "null"}');

      // 安全的ClientID获取
      const String envClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
      const String defaultClientId = Env.clientId;
      const String redirectUrl = String.fromEnvironment('SPOTIFY_REDIRECT_URL',
          defaultValue: Env.redirectUriMobile);

      final clientId = storedClientId ??
          (envClientId.isNotEmpty ? envClientId : defaultClientId);

      logger.d('Bootstrap: Using Client ID: ${clientId.substring(0, 8)}...');

      _spotifyService = SpotifyAuthService(
        clientId: clientId,
        redirectUrl: redirectUrl,
      );

      // 设置token刷新回调
      _spotifyService.onTokenRefreshed = onTokenRefreshed;

      _isInitialized = true;
      _initDone.complete();

      logger.d('Bootstrap: SpotifyService初始化完成');
    } catch (e) {
      logger.d('Bootstrap过程失败: $e');
      if (!_initDone.isCompleted) {
        _initDone.completeError(e);
      }
      rethrow;
    } finally {
      _isBootstrapping = false;
    }
  }

  /// 通用的服务调用保护器
  Future<T> guard<T>(Future<T> Function() job) async {
    await _initDone.future;
    return job();
  }

  /// 自动登录
  Future<void> autoLogin({
    required Future<void> Function() onSuccess,
  }) async {
    if (isLoading) {
      logger.d('跳过自动登录：已在加载中');
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      if (!_isInitialized) {
        throw SpotifyAuthException('SpotifyService 未初始化');
      }

      final token = await guard(() => _spotifyService.ensureFreshToken());
      if (token != null) {
        logger.d('自动登录：使用现有token成功');
        await _refreshUserProfile();
        await onSuccess();
      } else {
        logger.d('自动登录：未找到有效token，保持登出状态');
        if (username != null) {
          username = null;
        }
      }
    } catch (e) {
      logger.w('自动登录失败: $e');
      if (username != null) {
        username = null;
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 登录
  Future<void> login({
    required Future<void> Function() onSuccess,
  }) async {
    if (isLoading) {
      logger.w('登录操作已在进行中，跳过重复调用');
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      if (!_isInitialized) {
        throw SpotifyAuthException('SpotifyService 初始化失败');
      }

      logger.d('开始Spotify登录流程');
      final accessToken = await guard(() => _spotifyService.login());

      if (accessToken == null) {
        logger.w('登录返回null token，可能被用户取消');
      } else {
        logger.d('登录成功获取token，长度: ${accessToken.length}');
        if (username == null) await _refreshUserProfile();
        await onSuccess();
      }
    } catch (e) {
      logger.e('登录过程出错: $e');
      if (e is SpotifyAuthException && e.code == 'AUTH_CANCELLED') {
        logger.d('用户取消授权');
      } else {
        username = null;
        rethrow;
      }
    } finally {
      // iOS 的 isLoading 会在 handleCallbackToken 中重置
      final isIOSPlatform = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      if (!isIOSPlatform) {
        isLoading = false;
        notifyListeners();
        logger.d('登录流程结束，isLoading已重置为false');
      } else {
        logger.d('iOS登录流程：等待回调重置isLoading状态');
      }
    }
  }

  /// 登出
  Future<void> logout() async {
    bool wasLoading = isLoading;
    if (!wasLoading) {
      isLoading = true;
      notifyListeners();
    }

    try {
      if (isLoading) {
        logger.d('注销时重置isLoading状态');
        isLoading = false;
      }

      username = null;

      if (_isInitialized) {
        await guard(() => _spotifyService.logout());
      }
    } finally {
      if (!wasLoading) {
        isLoading = false;
      }
      notifyListeners();
    }
  }

  /// 处理从URL回调中获取的token
  Future<void> handleCallbackToken(
    String accessToken,
    String? expiresIn, {
    String? state,
    required Future<void> Function() onSuccess,
  }) async {
    logger.i('收到iOS授权回调，token长度: ${accessToken.length}');

    try {
      // 增强的安全验证
      if (!_isValidAccessToken(accessToken)) {
        logger.e('iOS回调：无效的access token格式');
        throw SpotifyAuthException('Invalid access token format',
            code: 'INVALID_TOKEN_FORMAT');
      }

      // CSRF 防护
      if (state != null) {
        if (!_verifyState(state)) {
          logger.e('iOS回调：State参数验证失败，可能的CSRF攻击');
          throw SpotifyAuthException('State parameter mismatch',
              code: 'CSRF_PROTECTION');
        }
      } else {
        logger.w('iOS回调：未提供state参数，跳过CSRF验证');
      }

      final expiresInSeconds = int.tryParse(expiresIn ?? '3600') ?? 3600;

      // 验证过期时间的合理性
      if (expiresInSeconds < 300 || expiresInSeconds > 7200) {
        logger.w('iOS回调：异常的token过期时间: ${expiresInSeconds}s, 使用默认值');
      }

      await guard(() => _spotifyService.saveAuthResponse(accessToken,
          expiresInSeconds: expiresInSeconds));
      logger.d('iOS回调：token已保存到安全存储');

      try {
        await _refreshUserProfile();
        await onSuccess();
        logger.i('iOS回调：成功保存access token并更新用户状态');
      } catch (profileError) {
        logger.e('iOS回调：获取用户资料失败: $profileError');
        try {
          _spotifyService.onTokenRefreshed?.call();
        } catch (e) {
          logger.w('调用token刷新回调失败: $e');
        }
      }
    } catch (e) {
      logger.e('保存回调token失败: $e');
    } finally {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
        logger.d('iOS回调：已重置isLoading状态');
      }
    }
  }

  /// 刷新用户资料
  Future<void> _refreshUserProfile() async {
    try {
      final user = await guard(() => _spotifyService.getUserProfile());
      username = user['display_name'];
      notifyListeners();
    } catch (e) {
      logger.w('刷新用户资料失败: $e');
    }
  }

  /// 设置 Client Credentials
  Future<void> setClientCredentials(
    String clientId, {
    required VoidCallback onTokenRefreshed,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_clientIdKey, clientId);

      logger.d('已保存新的ClientID到SharedPreferences: ${clientId.substring(0, 4)}...');

      final bool wasInitialized = _isInitialized;

      // 清除现有状态
      username = null;
      _isInitialized = false;

      // 如果之前已初始化并且已登录，先注销
      if (wasInitialized) {
        try {
          await guard(() => _spotifyService.logout());
        } catch (e) {
          logger.e('注销旧凭据时出错: $e');
        }
      }

      // 创建新的Completer
      _initDone = Completer<void>();

      // 用新凭据重新初始化服务
      const String redirectUrl = String.fromEnvironment('SPOTIFY_REDIRECT_URL',
          defaultValue: 'spotoolfy://callback');
      _spotifyService = SpotifyAuthService(
        clientId: clientId,
        redirectUrl: redirectUrl,
      );
      _spotifyService.onTokenRefreshed = onTokenRefreshed;
      _isInitialized = true;
      _initDone.complete();

      logger.d('已应用新的ClientID: ${clientId.substring(0, 4)}...');
      notifyListeners();
    } catch (e) {
      logger.e('设置客户端凭据失败: $e');
      rethrow;
    }
  }

  /// 获取 Client Credentials
  Future<Map<String, String?>> getClientCredentials() async {
    final sp = await SharedPreferences.getInstance();
    final clientId = sp.getString(_clientIdKey);
    return {
      'clientId': clientId,
    };
  }

  /// 重置 Client Credentials
  Future<void> resetClientCredentials({
    required VoidCallback onTokenRefreshed,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_clientIdKey);

    final bool wasInitialized = _isInitialized;
    username = null;
    _isInitialized = false;

    if (wasInitialized) {
      try {
        await guard(() => _spotifyService.logout());
      } catch (e) {
        logger.w('注销时出错: $e');
      }
    }

    _initDone = Completer<void>();
    await bootstrap(onTokenRefreshed: onTokenRefreshed);
    notifyListeners();
  }

  /// 检查授权状态和连接健康度
  Future<bool> checkAuthHealth() async {
    try {
      if (!_isInitialized) {
        return false;
      }

      final isAuth = await guard(() => _spotifyService.isAuthenticated());
      if (!isAuth) {
        logger.w('Auth Health: 未认证状态');
        return false;
      }

      try {
        final profile = await guard(() => _spotifyService.getUserProfile());
        if (profile['id'] != null) {
          logger.d('Auth Health: Token验证成功');
          return true;
        }
      } catch (e) {
        logger.w('Auth Health: Token验证失败: $e');
        return false;
      }

      return false;
    } catch (e) {
      logger.e('Auth Health: 检查失败: $e');
      return false;
    }
  }

  /// 验证 Access Token 格式
  bool _isValidAccessToken(String token) {
    if (token.isEmpty) return false;

    if (token.length < 50 || token.length > 500) {
      logger.w('Token长度异常: ${token.length}');
      return false;
    }

    final base64Regex = RegExp(r'^[A-Za-z0-9+/=_-]+$');
    if (!base64Regex.hasMatch(token)) {
      logger.w('Token包含无效字符');
      return false;
    }

    return true;
  }

  /// 生成 OAuth state 参数
  String generateState() {
    final random = math.Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final state = String.fromCharCodes(Iterable.generate(
        32, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
    _currentState = state;
    return state;
  }

  /// 验证 OAuth state 参数
  bool _verifyState(String? receivedState) {
    if (receivedState == null || _currentState == null) {
      logger.w('CSRF验证失败：state参数为空');
      return false;
    }

    final isValid = receivedState == _currentState;
    if (!isValid) {
      logger.e('CSRF验证失败：state参数不匹配');
      logger.d('期望: $_currentState, 收到: $receivedState');
    } else {
      logger.d('CSRF验证成功');
    }

    _currentState = null;
    return isValid;
  }

  /// 清除状态
  void clear() {
    username = null;
    isLoading = false;
  }
}
