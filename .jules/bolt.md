## 2025-02-12 - [Performance: Provider Selectors in List Views]
**Learning:** Rebuilding an entire screen (especially with list views, like `LyricsSelectionPage`) using `Consumer<Provider>` can cause significant UI jank, especially when listening to high-frequency state updates like `progress_ms`.
**Action:** Always prefer `Selector` to `Consumer` when dependent on a small subset of properties from a large provider state to scope rebuilds effectively and avoid unnecessary re-renders.

## 2026-03-08 - SpotifyPlaybackManager Sequential API Awaits
**Learning:** Background polling operations in Flutter/Dart, especially inside timers or microtasks, can introduce noticeable lag if multiple independent API calls (like fetching tracks, devices, and queues) are awaited sequentially. The delay compounds and increases the tick processing time.
**Action:** When performing periodic polling of multiple independent endpoints, always use `Future.wait()` to execute the calls concurrently, significantly reducing the overall duration of the tick and preventing UI/framework blockage.

## 2024-05-19 - Use `Future.wait` for independent API pagination requests
**Learning:** In Flutter, using sequential `await` calls in `for` loops to fetch independent API pages (like Spotify pagination) causes a waterfall effect, significantly increasing load times.
**Action:** Always batch independent asynchronous API calls using `Future.wait` when fetching multiple pages or independent datasets concurrently, provided the API rate limits (like Spotify's) permit it.

## 2024-05-19 - [Optimize Flutter Provider Selector for High-Frequency Streams]
**Learning:** When using `Selector` in Flutter with high-frequency streams (like audio playback `progressMs`), passing the raw rapidly changing value into the `builder` causes excessive widget rebuilds.
**Action:** Calculate the stable derived state (e.g., `currentLineIndex`) *inside* the `selector` callback and return a snapshot containing only the derived state. Update `shouldRebuild` to compare this derived state, ensuring the UI only rebuilds when visually necessary (e.g., when the lyric line changes, not on every millisecond tick).

## 2024-05-19 - Concurrent Preloading of Images
**Learning:** Sequential preloading of image URLs in a loop (using `await precacheImage()`) creates a network waterfall, significantly delaying UI rendering when multiple images are involved.
**Action:** When preloading a batch of images (e.g., in a manager like `SpotifyCacheManager`), always map the requests to Futures and execute them concurrently with `Future.wait()`.
