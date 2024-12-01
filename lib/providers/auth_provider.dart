import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => currentUser != null;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 监听认证状态变化
  AuthProvider() {
    _auth.authStateChanges().listen((User? user) {
      notifyListeners();
    });
  }

  // Google 登录
  Future<UserCredential?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      // 触发 Google 登录流程
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      // 获取认证信息
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      // 创建 Firebase 凭证
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 使用 Google 凭证登录 Firebase
      final userCredential = 
          await _auth.signInWithCredential(credential);
      
      return userCredential;
    } catch (e) {
      print('Google 登录失败: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 登出
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      print('登出失败: $e');
      rethrow;
    }
  }

  // 获取用户显示名称
  String? get userDisplayName => currentUser?.displayName;

  // 获取用户邮箱
  String? get userEmail => currentUser?.email;

  // 获取用户头像
  String? get userPhotoUrl => currentUser?.photoURL;
}
