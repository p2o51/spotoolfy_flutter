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
## 2026-03-23 - [Performance: Concurrent API Pagination]\n**Learning:** When fetching paginated API results (e.g., Spotify tracks) sequentially, the total time is O(N) where N is the number of pages. For APIs that support concurrent requests within rate limits, batching pagination requests using  can drastically reduce load times. However, you must statically calculate the offsets beforehand rather than relying on the length of a mutating list to avoid race conditions or missed pages.\n**Action:** When refactoring sequential pagination to concurrent batches, first calculate all required offsets using the known  count and , chunk the requests into safe batch sizes (e.g., 5), await them with , and then append the ordered results to the main collection.

## 2024-05-20 - [Performance: Concurrent API Pagination]
**Learning:** When fetching paginated API results (e.g., Spotify tracks) sequentially, the total time is O(N) where N is the number of pages. For APIs that support concurrent requests within rate limits, batching pagination requests using `Future.wait` can drastically reduce load times. However, you must statically calculate the offsets beforehand rather than relying on the length of a mutating list to avoid race conditions or missed pages.
**Action:** When refactoring sequential pagination to concurrent batches, first calculate all required offsets using the known `total` count and `limit`, chunk the requests into safe batch sizes (e.g., 5), await them with `Future.wait`, and then append the ordered results to the main collection.
