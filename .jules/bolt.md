## 2026-03-02 - [Parallelize SharedPreferences removals]
**Learning:** Sequential `await prefs.remove(key)` operations in loops for SharedPreferences keys can introduce unnecessary latency due to sequential disk I/O, especially when clearing large caches.
**Action:** Use `Future.wait(futures)` to parallelize multiple independent asynchronous removal operations to optimize performance.
