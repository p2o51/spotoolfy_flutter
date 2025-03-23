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
  List<Map<String, dynamic>> randomThoughts = [];
  
  String _currentRating = 'good';
  String get currentRating => _currentRating;

  List<Map<String, dynamic>> _recentPlayContexts = [];
  List<Map<String, dynamic>> get recentPlayContexts => _recentPlayContexts;

  void setRating(String rating) {
    _currentRating = rating;
    notifyListeners();
  }

  bool get isLoading => _isLoading;

  FirestoreProvider(this._authProvider, this._spotifyProvider) {
    _spotifyProvider.addListener(_onTrackChanged);
    fetchRecentPlayContexts();
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

      if (currentTrackThoughts.isNotEmpty) {
        _currentRating = currentTrackThoughts.first['rating'];
        print("Fetched rating: $_currentRating");
      } else {
        _currentRating = 'good';
      }

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
            'rating': _currentRating,
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
        randomThoughts = [];
      } else {
        // For backward compatibility, keep the randomThought
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

        // Get 3 random thoughts
        randomThoughts = [];
        final totalDocs = thoughtsSnap.docs.length;
        final usedIndices = <int>{};
        
        // Get up to 3 random thoughts (or less if fewer are available)
        final numToGet = totalDocs < 3 ? totalDocs : 3;
        
        for (var i = 0; i < numToGet; i++) {
          int randomIndex;
          do {
            randomIndex = DateTime.now().microsecondsSinceEpoch % totalDocs;
          } while (usedIndices.contains(randomIndex) && usedIndices.length < totalDocs);
          
          if (usedIndices.length >= totalDocs) break;
          usedIndices.add(randomIndex);
          
          final doc = thoughtsSnap.docs[randomIndex];
          randomThoughts.add({
            'id': doc.id,
            ...doc.data(),
            'createdAt': (doc.data()['createdAt'] as Timestamp).toDate().toString(),
            'timestamp': doc.data()['timestamp'] ?? '',
            'album': doc.data()['album'] ?? '',
            'imageUrl': doc.data()['imageUrl'] ?? '',
          });
        }
      }

      notifyListeners();
    } catch (e) {
      print('获取随机笔记失败: $e');
      randomThought = null;
      randomThoughts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 存储播放上下文到 Firestore
  Future<void> savePlayContext({
    required String trackId,
    required Map<String, dynamic> context,
    required DateTime timestamp,
  }) async {
    if (_authProvider.currentUser == null) return;

    try {
      final userId = _authProvider.currentUser!.uid;
      final contextUri = context['uri'] as String;
      
      // 先检查是否已存在相同的 context
      final existingDocs = await _firestore
          .collection('users/$userId/playContexts')
          .where('uri', isEqualTo: contextUri)
          .get();

      if (existingDocs.docs.isNotEmpty) {
        // 如果存在，更新时间戳
        await existingDocs.docs.first.reference.update({
          'timestamp': timestamp,
        });
      } else {
        // 如果不存在，创建新文档
        await _firestore
            .collection('users/$userId/playContexts')
            .doc()
            .set({
          'context': context,
          'timestamp': timestamp,
          'type': context['type'],
          'uri': contextUri,
          'name': context['name'],
          'images': context['images'],
          'external_urls': context['external_urls'],
        });
      }

      await fetchRecentPlayContexts();

    } catch (e) {
      print('保存播放上下文失败: $e');
    }
  }

  // 获取最近的播放上下文
  Future<void> fetchRecentPlayContexts() async {
    if (_authProvider.currentUser == null) return;

    try {
      final userId = _authProvider.currentUser!.uid;
      
      final snapshot = await _firestore
          .collection('users/$userId/playContexts')
          .orderBy('timestamp', descending: true)
          .limit(50)  // 限制获取数量
          .get();

      _recentPlayContexts = snapshot.docs
          .map((doc) => doc.data())
          .toList();
      
      notifyListeners();

    } catch (e) {
      print('获取播放上下文失败: $e');
      _recentPlayContexts = [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _spotifyProvider.removeListener(_onTrackChanged);
    super.dispose();
  }
}