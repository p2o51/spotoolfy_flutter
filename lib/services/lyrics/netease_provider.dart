import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/export.dart';
import 'lyric_provider.dart';

/// 网易云音乐歌词提供者
class NetEaseProvider extends LyricProvider {
  static const String _baseUrl = 'https://music.163.com/weapi';
  final Logger _logger = Logger();
  
  // 网易云API加密参数
  static const String _presetKey = '0CoJUm6Qyw8W8jud';
  static const String _iv = '0102030405060708';
  static const String _publicKey = '010001';
  static const String _modulus = '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static const String _nonce = '0123456789abcdef';
  
  final Map<String, String> _headers = {
    'referer': 'https://music.163.com/',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36',
    'content-type': 'application/x-www-form-urlencoded',
  };

  @override
  String get name => 'netease';

  @override
  Future<SongMatch?> search(String title, String artist) async {
    try {
      final keyword = '$title $artist';
      final params = {
        's': keyword,
        'type': '1', // 1表示单曲
        'limit': '3',
        'offset': '0',
      };
      
      final encryptedData = _encryptRequest(params);
      final response = await http.post(
        Uri.parse('$_baseUrl/cloudsearch/get/web'),
        headers: _headers,
        body: encryptedData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w('网易云搜索请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      if (data['code'] == 200 && data['result']?['songs']?.isNotEmpty) {
        final songData = data['result']['songs'][0];
        return SongMatch(
          songId: songData['id'].toString(),
          title: songData['name'] ?? title,
          artist: songData['ar']?[0]?['name'] ?? artist,
        );
      } else if (data['code'] == 50000005) {
        _logger.w('网易云API需要登录');
      }
      return null;
    } catch (e) {
      _logger.e('网易云搜索歌曲失败: $e');
      return null;
    }
  }

  @override
  Future<String?> fetchLyric(String songId) async {
    try {
      final params = {
        'id': songId,
        'lv': '-1',
        'kv': '-1',
        'tv': '-1',
      };
      
      final encryptedData = _encryptRequest(params);
      final response = await http.post(
        Uri.parse('$_baseUrl/song/lyric'),
        headers: _headers,
        body: encryptedData,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logger.w('网易云获取歌词请求失败，状态码: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      if (data['code'] == 200 && data['lrc']?['lyric'] != null) {
        return data['lrc']['lyric'];
      } else if (data['code'] == 50000005) {
        _logger.w('网易云API需要登录');
      }
      return null;
    } catch (e) {
      _logger.e('网易云获取歌词详情失败: $e');
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
