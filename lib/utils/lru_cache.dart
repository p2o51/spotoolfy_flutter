import 'dart:collection';

/// LRU (Least Recently Used) 缓存实现
///
/// 当缓存达到最大容量时，自动移除最久未使用的项目
class LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  LruCache({required this.maxSize}) : assert(maxSize > 0);

  /// 获取缓存项
  ///
  /// 如果项存在，将其移动到最近使用位置
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // 移动到最近使用位置
    final value = _cache.remove(key);
    _cache[key] = value as V;
    return value;
  }

  /// 添加或更新缓存项
  ///
  /// 如果达到最大容量，移除最久未使用的项
  void put(K key, V value) {
    // 如果 key 已存在，先移除再添加（移到末尾）
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      // 移除最久未使用的项（第一个）
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// 检查是否包含指定的 key
  bool containsKey(K key) => _cache.containsKey(key);

  /// 移除指定的 key
  V? remove(K key) => _cache.remove(key);

  /// 清空缓存
  void clear() => _cache.clear();

  /// 当前缓存大小
  int get length => _cache.length;

  /// 缓存是否为空
  bool get isEmpty => _cache.isEmpty;

  /// 缓存是否已满
  bool get isFull => _cache.length >= maxSize;

  /// 获取所有 keys
  Iterable<K> get keys => _cache.keys;

  /// 获取所有 values
  Iterable<V> get values => _cache.values;

  /// 批量添加
  void putAll(Map<K, V> entries) {
    for (final entry in entries.entries) {
      put(entry.key, entry.value);
    }
  }

  /// 获取或计算值
  ///
  /// 如果 key 不存在，使用 ifAbsent 计算值并缓存
  V putIfAbsent(K key, V Function() ifAbsent) {
    final existing = get(key);
    if (existing != null) return existing;

    final value = ifAbsent();
    put(key, value);
    return value;
  }

  @override
  String toString() => 'LruCache(size: $length/$maxSize)';
}

/// 带 TTL (Time To Live) 的 LRU 缓存
///
/// 除了 LRU 策略外，还会根据时间自动过期
class TtlLruCache<K, V> {
  final int maxSize;
  final Duration ttl;
  final LinkedHashMap<K, _TtlEntry<V>> _cache = LinkedHashMap<K, _TtlEntry<V>>();

  TtlLruCache({required this.maxSize, required this.ttl})
      : assert(maxSize > 0);

  /// 获取缓存项
  ///
  /// 如果项已过期，返回 null 并移除
  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;

    // 检查是否过期
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    // 移动到最近使用位置
    _cache.remove(key);
    _cache[key] = entry;
    return entry.value;
  }

  /// 添加或更新缓存项
  void put(K key, V value) {
    // 如果 key 已存在，先移除再添加
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      // 移除最久未使用的项
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _TtlEntry(value, DateTime.now().add(ttl));
  }

  /// 检查是否包含指定的 key（不考虑过期）
  bool containsKey(K key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// 移除指定的 key
  V? remove(K key) => _cache.remove(key)?.value;

  /// 清空缓存
  void clear() => _cache.clear();

  /// 清理所有过期项
  void evictExpired() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }

  /// 当前缓存大小
  int get length => _cache.length;

  /// 缓存是否为空
  bool get isEmpty => _cache.isEmpty;

  @override
  String toString() => 'TtlLruCache(size: $length/$maxSize, ttl: $ttl)';
}

class _TtlEntry<V> {
  final V value;
  final DateTime expiresAt;

  _TtlEntry(this.value, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
