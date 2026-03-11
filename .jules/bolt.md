## 2024-05-19 - Use `Future.wait` for independent API pagination requests
**Learning:** In Flutter, using sequential `await` calls in `for` loops to fetch independent API pages (like Spotify pagination) causes a waterfall effect, significantly increasing load times.
**Action:** Always batch independent asynchronous API calls using `Future.wait` when fetching multiple pages or independent datasets concurrently, provided the API rate limits (like Spotify's) permit it.
