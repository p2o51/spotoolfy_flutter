import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/export.dart';
import 'lyric_provider.dart';

// Simple class to hold the cookie and its expiration time
class _CookieStore {
  String? value;
  DateTime? expire;

  bool get isValid {
    return value != null &&
           expire != null &&
           expire!.isAfter(DateTime.now().add(const Duration(minutes: 5))); // Add a 5-minute buffer
  }
}

/// 网易云音乐歌词提供者
class NetEaseProvider extends LyricProvider {
  static const String _baseUrl = 'https://music.163.com/weapi';
  final Logger _logger = Logger();
  final _CookieStore _guestCookie = _CookieStore(); // Instance for guest cookie
  
  // 网易云API加密参数
  static const String _presetKey = '0CoJUm6Qyw8W8jud';
  static const String _iv = '0102030405060708';
  static const String _publicKey = '010001';
  static const String _modulus = '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static const String _nonce = '0123456789abcdef';
  
  final Map<String, String> _baseHeaders = { // Renamed to avoid conflict in methods
    'referer': 'https://music.163.com/',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36',
    'content-type': 'application/x-www-form-urlencoded',
    'os': 'pc', // Add os=pc globally as suggested
  };

  @override
  String get name => 'netease';

  /// Ensures a valid guest cookie is available, fetching one if necessary.
  Future<String> _ensureGuestCookie() async {
    if (_guestCookie.isValid) {
      _logger.d('Using existing guest cookie.');
      return _guestCookie.value!;
    }

    _logger.i('Guest cookie invalid or missing, fetching new one...');
    try {
      final encryptedData = _encryptRequest({}); // Empty object for anonymous registration
      final response = await http.post(
        Uri.parse('https://music.163.com/weapi/register/anonimous'),
        headers: _baseHeaders, // Use base headers, no cookie needed for this request
        body: encryptedData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
         throw Exception('游客登录请求失败，状态码: ${response.statusCode}, Body: ${response.body}');
      }

      final data = json.decode(response.body);
      if (data['code'] == 200 && data['cookie'] != null) {
        _guestCookie.value = data['cookie'];
        // Set expiration (e.g., 20 hours from now as suggested)
        _guestCookie.expire = DateTime.now().add(const Duration(hours: 20)); 
        _logger.i('游客登录成功，获取到新的Cookie.');
        // Store cookie persistently? (Future enhancement based on plan)
        // For now, it's in memory.
        return _guestCookie.value!;
      } else {
        throw Exception('游客登录API返回错误: $data');
      }
    } catch (e) {
      _logger.e('获取游客Cookie失败: $e');
      // Invalidate cookie on error so next call retries
      _guestCookie.value = null; 
      _guestCookie.expire = null;
      rethrow; // Rethrow to let caller handle it
    }
  }

  @override
  Future<SongMatch?> search(String title, String artist) async {
    try {
      final cookie = await _ensureGuestCookie(); // Get cookie first
      final keyword = '$title $artist';
      final params = {
        's': keyword,
        'type': '1', // 1表示单曲
        'limit': '3',
        'offset': '0',
      };
      
      final encryptedData = _encryptRequest(params);
      final headersWithCookie = {
        ..._baseHeaders,
        'cookie': cookie, // Use the obtained guest cookie
      };
      
      final response = await http.post(
        Uri.parse('$_baseUrl/cloudsearch/get/web'),
        headers: headersWithCookie, // Send request with cookie
        body: encryptedData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w('网易云搜索请求失败，状态码: ${response.statusCode}');
        // Check if it's a login error (e.g., cookie expired)
        try {
          final errorData = json.decode(response.body);
          if (errorData['code'] == 301 || errorData['code'] == 50000005) {
             _logger.w('搜索时Cookie失效 (${errorData['code']}), 清除本地Cookie.');
             _guestCookie.value = null; // Invalidate cookie
             _guestCookie.expire = null;
             // Optionally retry once? For now, let it fail and next call will refresh.
          }
        } catch (_) { /* Ignore potential JSON parsing error */ }
        return null;
      }

      final data = json.decode(response.body);
      // Handle successful response or specific login error
      if (data['code'] == 200 && data['result']?['songs']?.isNotEmpty) {
        final songData = data['result']['songs'][0];
        return SongMatch(
          songId: songData['id'].toString(),
          title: songData['name'] ?? title,
          artist: songData['ar']?[0]?['name'] ?? artist,
        );
      } else if (data['code'] == 301 || data['code'] == 50000005) {
        // This case might happen if _ensureGuestCookie succeeded but the cookie immediately became invalid
        _logger.w('网易云API需要登录或Cookie失效 (Code: ${data['code']})');
        _guestCookie.value = null; // Invalidate cookie
        _guestCookie.expire = null;
        return null; // Let the next call attempt to re-login
      } else {
        _logger.w('网易云搜索返回非预期结果: $data');
        return null;
      }
    } catch (e) {
      _logger.e('网易云搜索歌曲失败: $e');
      // If the error was during cookie fetch, it's already invalidated.
      return null;
    }
  }

  @override
  Future<String?> fetchLyric(String songId) async {
    try {
      final cookie = await _ensureGuestCookie(); // Get cookie first
      final params = {
        'id': songId,
        'lv': '-1',
        'kv': '-1',
        'tv': '-1',
      };
      
      final encryptedData = _encryptRequest(params);
       final headersWithCookie = {
        ..._baseHeaders,
        'cookie': cookie, // Use the obtained guest cookie
      };
      
      final response = await http.post(
        Uri.parse('$_baseUrl/song/lyric'),
        headers: headersWithCookie, // Send request with cookie
        body: encryptedData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w('网易云获取歌词请求失败，状态码: ${response.statusCode}');
        // Check if it's a login error (e.g., cookie expired)
         try {
          final errorData = json.decode(response.body);
          if (errorData['code'] == 301 || errorData['code'] == 50000005) {
             _logger.w('获取歌词时Cookie失效 (${errorData['code']}), 清除本地Cookie.');
             _guestCookie.value = null; // Invalidate cookie
             _guestCookie.expire = null;
          }
        } catch (_) { /* Ignore potential JSON parsing error */ }
        return null;
      }

      final data = json.decode(response.body);
      if (data['code'] == 200 && data['lrc']?['lyric'] != null) {
        return data['lrc']['lyric'];
      } else if (data['code'] == 301 || data['code'] == 50000005) {
        _logger.w('网易云API需要登录或Cookie失效 (Code: ${data['code']})');
        _guestCookie.value = null; // Invalidate cookie
        _guestCookie.expire = null;
        return null; // Let the next call attempt to re-login
      } else {
         _logger.w('网易云获取歌词返回非预期结果: $data');
        return null;
      }
    } catch (e) {
      _logger.e('网易云获取歌词详情失败: $e');
      // If the error was during cookie fetch, it's already invalidated.
      return null;
    }
  }

  /// 加密请求参数
  Map<String, String> _encryptRequest(Map<String, dynamic> params) {
    // 第一次AES加密
    final paramsJson = json.encode(params);
    final secretKey = _createSecretKey(16);
    final firstEncrypt = _aesEncrypt(paramsJson, _presetKey);
    
    // 第二次AES加密
    final secondEncrypt = _aesEncrypt(firstEncrypt, secretKey);
    
    // RSA加密
    final encSecKey = _rsaEncrypt(secretKey);
    
    return {
      'params': secondEncrypt,
      'encSecKey': encSecKey,
    };
  }

  /// AES加密
  String _aesEncrypt(String text, String key) {
    final keyBytes = Key(utf8.encode(key));
    final ivBytes = IV(utf8.encode(_iv));
    final encrypter = Encrypter(AES(keyBytes, mode: AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encrypt(text, iv: ivBytes);
    return encrypted.base64;
  }

  /// RSA加密（网易云使用的是无填充模式）
  String _rsaEncrypt(String text) {
    // 反转并填充到256字节
    final reversedText = text.split('').reversed.join('');
    final textBytes = utf8.encode(reversedText);
    
    // 转换为大整数
    final biText = _bytesToBigInt(textBytes);
    final biExp = BigInt.parse(_publicKey, radix: 16);
    final biMod = BigInt.parse(_modulus, radix: 16);
    
    // 幂运算: biText^biExp % biMod
    final biRet = biText.modPow(biExp, biMod);
    
    // 转换为16进制字符串，确保长度为256
    String hexRet = biRet.toRadixString(16);
    if (hexRet.length < 256) {
      hexRet = hexRet.padLeft(256, '0');
    }
    
    return hexRet;
  }

  /// 生成指定长度的随机字符串
  String _createSecretKey(int size) {
    final random = Random.secure();
    final result = List.generate(size, (_) => _nonce[random.nextInt(_nonce.length)]).join();
    return result;
  }

  /// 字节数组转BigInt
  BigInt _bytesToBigInt(List<int> bytes) {
    BigInt result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
