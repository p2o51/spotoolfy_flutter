import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_provider.dart';
import 'spotify_provider.dart';

class FirestoreProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthProvider _authProvider;
  final SpotifyProvider _spotifyProvider;
  
  List<Map<String, dynamic>> currentTrackThoughts = [];
  List<Map<String, dynamic>> homoThoughts = [];
  bool _isLoading = false;
  String? _lastTrackId;
  
  Map<String, dynamic>? randomThought;
  
  bool get isLoading => _isLoading;

  FirestoreProvider(this._authProvider, this._spotifyProvider) {
    _spotifyProvider.addListener(_onTrackChanged);
  }

  void _onTrackChanged() {
    final currentTrackId = _spotifyProvider.currentTrack?['item']?['id'];
    if (currentTrackId != null && currentTrackId != _lastTrackId) {
      _lastTrackId = currentTrackId;
      fetchThoughts();
    }
  }

  // 获取当前歌曲的想法
  Future<void> fetchThoughts() async {
    if (_authProvider.currentUser == null ||
        _spotifyProvider.currentTrack == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      final trackId = _spotifyProvider.currentTrack!['item']['id'];
      final trackName = _spotifyProvider.currentTrack!['item']['name'];
      final userId = _authProvider.currentUser!.uid;

      // 获取当前版本的想法
      final thoughtsSnap = await _firestore
          .collection('users/$userId/thoughts')
          .where('trackId', isEqualTo: trackId)
          .orderBy('createdAt', descending: true)
          .get();

      currentTrackThoughts = thoughtsSnap.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
        'createdAt': (doc.data()['createdAt'] as Timestamp).toDate().toString(),
        'timestamp': doc.data()['timestamp'] ?? '',
        'album': doc.data()['album'] ?? '',
        'imageUrl': doc.data()['imageUrl'] ?? '',
      }).toList();

      // 获取同名歌曲的想法
      final homoSnap = await _firestore
          .collection('users/$userId/thoughts')
          .where('trackName', isEqualTo: trackName)
          .where('trackId', isNotEqualTo: trackId)
          .orderBy('createdAt', descending: true)
          .get();

      homoThoughts = homoSnap.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
        'createdAt': (doc.data()['createdAt'] as Timestamp).toDate().toString(),
        'timestamp': doc.data()['timestamp'] ?? '',
        'album': doc.data()['album'] ?? '',
        'imageUrl': doc.data()['imageUrl'] ?? '',
      }).toList();

      notifyListeners();
    } catch (e) {
      print('获取想法失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 添加新想法
  Future<void> addThought({
    required String content,
  }) async {
    if (_authProvider.currentUser == null ||
        _spotifyProvider.currentTrack == null) return;

    try {
      final userId = _authProvider.currentUser!.uid;
      final track = _spotifyProvider.currentTrack!['item'];
      final progressMs = _spotifyProvider.currentTrack!['progress_ms'];
      final timestamp = progressMs;
      final album = track['album']['name'];
      final imageUrl = track['album']['images'][0]['url'];

      await _firestore
          .collection('users/$userId/thoughts')
          .add({
            'content': content,
            'rating': 'good',
            'trackId': track['id'],
            'trackName': track['name'],
            'artistName': (track['artists'] as List)
                .map((artist) => artist['name'])
                .join(', '),
            'createdAt': FieldValue.serverTimestamp(),
            'timestamp': timestamp,
            'album': album,
            'imageUrl': imageUrl,
          });

      await fetchThoughts();  // 刷新列表
    } catch (e) {
      print('添加想法失败: $e');
      rethrow;
    }
  }

  // 获取随机笔记
  Future<void> fetchRandomThought() async {
    if (_authProvider.currentUser == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      final userId = _authProvider.currentUser!.uid;

      // 获取所有笔记
      final thoughtsSnap = await _firestore
          .collection('users/$userId/thoughts')
          .get();

      if (thoughtsSnap.docs.isEmpty) {
        randomThought = null;
      } else {
        // 随机选择一条笔记
        final random = thoughtsSnap.docs[
          DateTime.now().millisecondsSinceEpoch % thoughtsSnap.docs.length
        ];

        randomThought = {
          'id': random.id,
          ...random.data(),
          'createdAt': (random.data()['createdAt'] as Timestamp).toDate().toString(),
          'timestamp': random.data()['timestamp'] ?? '',
          'album': random.data()['album'] ?? '',
          'imageUrl': random.data()['imageUrl'] ?? '',
        };
      }

      notifyListeners();
    } catch (e) {
      print('获取随机笔记失败: $e');
      randomThought = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _spotifyProvider.removeListener(_onTrackChanged);
    super.dispose();
  }
}