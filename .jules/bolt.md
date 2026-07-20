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

## 2024-10-24 - [Optimize Pagination APIs with Concurrent Batching]
**Learning:** Using an infinite `while (true)` loop with sequential HTTP requests and arbitrary network delays for fetching fully paginated data causes significant performance bottlenecks as the size of the dataset grows. The overall latency becomes the sum of all individual network request times and delays.
**Action:** First fetch the initial page to determine the total item count. Then, pre-calculate all necessary offsets and process them concurrently in chunks (e.g., batches of 5) using `Future.wait()`, inserting rate-limit delays *between* batches instead of after every individual request.

## 2025-05-18 - [API Rate Limit Scaling with Concurrent Batching]
**Learning:** When refactoring sequential API requests into concurrent batches, maintaining the original per-request delay but applying it *per-batch* effectively spikes the throughput (e.g. from 1 req / 200ms to 5 reqs / 200ms). This breaks explicit domain-knowledge safeguards and quickly exhausts rate limits (like Spotify's 180 requests per 30s), causing `429 Too Many Requests` exceptions.
**Action:** Always scale the inserted delay proportionally to the batch size. If the original safe limit was 200ms per request, a batch of 5 concurrent requests must be followed by a `200ms * batchSize` (1000ms) delay to preserve the same safe throughput limit.
