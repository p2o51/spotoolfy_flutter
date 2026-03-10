## 2025-02-12 - [Performance: Provider Selectors in List Views]
**Learning:** Rebuilding an entire screen (especially with list views, like `LyricsSelectionPage`) using `Consumer<Provider>` can cause significant UI jank, especially when listening to high-frequency state updates like `progress_ms`.
**Action:** Always prefer `Selector` to `Consumer` when dependent on a small subset of properties from a large provider state to scope rebuilds effectively and avoid unnecessary re-renders.
