import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'spotify_service.dart';

/// Spotify API 客户端
///
/// 封装通用的 HTTP 请求逻辑，减少重复代码
class SpotifyApiClient {
  final Logger _logger;
  final Future<String?> Function() _getAccessToken;

  static const String _baseUrl = 'https://api.spotify.com/v1';

  SpotifyApiClient({
    required Logger logger,
    required Future<String?> Function() getAccessToken,
  })  : _logger = logger,
        _getAccessToken = getAccessToken;

  /// 构建 API URI
  Uri buildUri(String path, [Map<String, String>? query]) {
    return Uri.https('api.spotify.com', '/v1$path',
        query?.isEmpty ?? true ? null : query);
  }

  /// 创建认证请求头
  Future<Map<String, String>> authHeaders({bool hasBody = true}) async {
    final token = await _getAccessToken();
    if (token == null) {
      throw SpotifyAuthException('未认证或授权已过期', code: '401');
    }
    return {
      'Authorization': 'Bearer $token',
      if (hasBody) 'Content-Type': 'application/json',
    };
  }

  /// 通用的网络重试包装器
  Future<T> withNetworkRetry<T>(
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
          _logger.d('$operationName: 网络错误，尝试第 $retryCount 次重试: $e');
          await Future.delayed(baseDelay * retryCount);
          continue;
        }

        if (isRetryableNetworkError) {
          throw SpotifyAuthException(
              '$operationName 时出错: 网络连接失败，已尝试 $maxRetries 次',
              code: 'NETWORK_RETRY_EXHAUSTED');
        } else {
          throw SpotifyAuthException('$operationName 时出错: $e',
              code: 'OPERATION_FAILED_UNKNOWN');
        }
      }
    }

    throw SpotifyAuthException('$operationName 时出错: 未知错误',
        code: 'RETRY_LOGIC_ERROR');
  }

  /// GET 请求
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final headers = await authHeaders(hasBody: false);
      final uri = Uri.parse('$_baseUrl$endpoint');

      final response = await http.get(uri, headers: headers);
      return _handleResponse(response, 'GET $endpoint');
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API GET 请求失败: $e');
    }
  }

  /// GET 请求（返回可能为空）
  Future<Map<String, dynamic>?> getOptional(String endpoint) async {
    try {
      final headers = await authHeaders(hasBody: false);
      final uri = Uri.parse('$_baseUrl$endpoint');

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 204) {
        return null;
      }

      return _handleResponse(response, 'GET $endpoint');
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API GET 请求失败: $e');
    }
  }

  /// PUT 请求
  Future<Map<String, dynamic>?> put(String endpoint,
      {Map<String, dynamic>? body}) async {
    try {
      final headers = await authHeaders(hasBody: body != null);
      final uri = Uri.parse('$_baseUrl$endpoint');

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
      }

      return _handleResponse(response, 'PUT $endpoint');
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API PUT 请求失败: $e');
    }
  }

  /// POST 请求
  Future<Map<String, dynamic>?> post(String endpoint,
      {Map<String, dynamic>? body}) async {
    try {
      final headers = await authHeaders(hasBody: body != null);
      final uri = Uri.parse('$_baseUrl$endpoint');

      final response = await http.post(
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
      }

      return _handleResponse(response, 'POST $endpoint');
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API POST 请求失败: $e');
    }
  }

  /// DELETE 请求
  Future<void> delete(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final headers = await authHeaders(hasBody: body != null);
      final uri = Uri.parse('$_baseUrl$endpoint');

      final response = await http.delete(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        _handleResponse(response, 'DELETE $endpoint');
      }
    } catch (e) {
      if (e is SpotifyAuthException) rethrow;
      throw SpotifyAuthException('API DELETE 请求失败: $e');
    }
  }

  /// 处理响应
  Map<String, dynamic> _handleResponse(http.Response response, String operation) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw SpotifyAuthException('授权已过期或无效', code: '401');
    } else if (response.statusCode == 404) {
      throw SpotifyAuthException('$operation: 资源不存在', code: '404');
    } else {
      throw SpotifyAuthException(
        '$operation 失败: ${response.body}',
        code: response.statusCode.toString(),
      );
    }
  }

  /// 控制类请求（播放/暂停等）
  ///
  /// 这些请求可能需要设备ID重试
  Future<void> controlRequest(
    String path, {
    String method = 'PUT',
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
    required Future<List<Map<String, dynamic>>> Function() getDevices,
  }) async {
    Future<http.Response> makeRequest(Map<String, String> queryParams) async {
      final uri = buildUri(path, queryParams.isEmpty ? null : queryParams);
      final headers = await authHeaders(hasBody: body != null);

      if (method == 'POST') {
        return http.post(uri,
            headers: headers, body: body != null ? jsonEncode(body) : null);
      } else {
        return http.put(uri,
            headers: headers, body: body != null ? jsonEncode(body) : null);
      }
    }

    // 首次尝试
    var response = await makeRequest(query);

    bool isSuccess = response.statusCode == 204 ||
        response.statusCode == 202 ||
        response.statusCode == 200;

    if (isSuccess) {
      return;
    }

    if (response.statusCode == 401) {
      throw SpotifyAuthException('授权已过期或无效', code: '401');
    }

    // 尝试使用设备ID重试
    _logger.d('控制请求失败 (${response.statusCode})，尝试获取设备列表重试...');

    final devices = await getDevices();
    if (devices.isEmpty) {
      throw SpotifyAuthException('找不到可用播放设备', code: 'NO_DEVICE_ON_RETRY');
    }

    final activeDevice =
        devices.firstWhere((d) => d['is_active'] == true, orElse: () => devices.first);
    final deviceId = activeDevice['id'] as String?;

    if (deviceId == null) {
      throw SpotifyAuthException('无法获取设备ID', code: 'NO_DEVICE_ID');
    }

    // 使用设备ID重试
    final retryQuery = Map<String, String>.from(query);
    retryQuery['device_id'] = deviceId;

    response = await makeRequest(retryQuery);

    isSuccess = response.statusCode == 204 ||
        response.statusCode == 202 ||
        response.statusCode == 200;

    if (isSuccess) {
      return;
    }

    throw SpotifyAuthException('控制失败 (重试后): ${response.body}',
        code: response.statusCode.toString());
  }
}
