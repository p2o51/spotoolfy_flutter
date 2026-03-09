## 2024-05-24 - [Avoid Sequential Awaits in Spotify API Refresh]
**Learning:** Sequential `await` calls for independent asynchronous operations (like refreshing tracks, devices, and queue from Spotify API) create unnecessary bottlenecks and accumulate latency. The `SpotifyPlaybackManager` was suffering from this pattern.
**Action:** Use `Future.wait` to parallelize multiple independent asynchronous operations, specifically in the initialization and refresh cycles of API orchestrators, to minimize total execution time.
