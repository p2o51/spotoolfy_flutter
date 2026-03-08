## 2026-03-08 - SpotifyPlaybackManager Sequential API Awaits
**Learning:** Background polling operations in Flutter/Dart, especially inside timers or microtasks, can introduce noticeable lag if multiple independent API calls (like fetching tracks, devices, and queues) are awaited sequentially. The delay compounds and increases the tick processing time.
**Action:** When performing periodic polling of multiple independent endpoints, always use `Future.wait()` to execute the calls concurrently, significantly reducing the overall duration of the tick and preventing UI/framework blockage.
