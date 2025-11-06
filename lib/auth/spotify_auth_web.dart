// ignore_for_file: deprecated_member_use

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../env.dart';
import '../utils/effective_redirect_uri.dart';

class SpotifyAuthWeb {
  static final SpotifyAuthWeb _i = SpotifyAuthWeb._();
  SpotifyAuthWeb._();
  factory SpotifyAuthWeb() => _i;

  static const _authBase = 'https://accounts.spotify.com';
  static const _authorizePath = '/authorize';
  static const _tokenPath = '/api/token';

  static const _kVerifier = 'sp_code_verifier';
  static const _kAccessToken = 'sp_access_token';
  static const _kRefreshToken = 'sp_refresh_token';
  static const _kExpiresAt = 'sp_expires_at';
  static const _kState = 'sp_state';

  String _randomString(int len) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _base64UrlNoPad(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  Future<String> _sha256b64(String input) async {
    final hash = sha256.convert(utf8.encode(input));
    return _base64UrlNoPad(hash.bytes);
  }

  Future<void> startLogin() async {
    final verifier = _randomString(64);
    final challenge = await _sha256b64(verifier);
    html.window.localStorage[_kVerifier] = verifier;
    final state = _randomString(32);
    html.window.localStorage[_kState] = state;
    final redirectUri = effectiveRedirectUri();

    final params = {
      'client_id': Env.clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': Env.scopes.join(' '),
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
    };

    final authUrl =
        Uri.parse('$_authBase$_authorizePath').replace(queryParameters: params);
    html.window.location.assign(authUrl.toString());
  }

  Future<bool> handleRedirect() async {
    final qp = Uri.base.queryParameters;
    final code = qp['code'];
    final error = qp['error'];
    if (error != null) {
      html.window.localStorage.remove(_kState);
      return false;
    }
    if (code == null) return false;

    final returnedState = qp['state'];
    final storedState = html.window.localStorage[_kState];
    if (storedState == null || storedState != returnedState) {
      html.window.localStorage.remove(_kState);
      return false;
    }
    html.window.localStorage.remove(_kState);

    final verifier = html.window.localStorage[_kVerifier];
    if (verifier == null) return false;

    final redirectUri = effectiveRedirectUri();
    final body = {
      'client_id': Env.clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    };

    final resp = await http.post(
      Uri.parse('$_authBase$_tokenPath'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200 || json['access_token'] == null) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    html.window.localStorage[_kAccessToken] = json['access_token'] as String;
    html.window.localStorage[_kRefreshToken] =
        (json['refresh_token'] ?? '') as String;
    html.window.localStorage[_kExpiresAt] = '${now + expiresIn}';

    html.window.history.replaceState(null, 'spotoolfy', '/');
    return true;
  }

  bool _isExpired() {
    final expStr = html.window.localStorage[_kExpiresAt];
    if (expStr == null) return true;
    final exp = int.tryParse(expStr) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= (exp - 30);
  }

  Future<void> _refresh() async {
    final refreshToken = html.window.localStorage[_kRefreshToken];
    if (refreshToken == null || refreshToken.isEmpty) return;

    final resp = await http.post(
      Uri.parse('$_authBase$_tokenPath'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': Env.clientId,
      },
    );
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200 && json['access_token'] != null) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      html.window.localStorage[_kAccessToken] = json['access_token'] as String;
      if (json['refresh_token'] != null) {
        html.window.localStorage[_kRefreshToken] =
            json['refresh_token'] as String;
      }
      html.window.localStorage[_kExpiresAt] = '${now + expiresIn}';
    } else {
      logout();
    }
  }

  Future<String?> getValidAccessToken() async {
    var token = html.window.localStorage[_kAccessToken];
    if (token == null || _isExpired()) {
      await _refresh();
      token = html.window.localStorage[_kAccessToken];
    }
    return token;
  }

  void logout() {
    html.window.localStorage.remove(_kAccessToken);
    html.window.localStorage.remove(_kRefreshToken);
    html.window.localStorage.remove(_kExpiresAt);
    html.window.localStorage.remove(_kVerifier);
    html.window.localStorage.remove(_kState);
  }
}
