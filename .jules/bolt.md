## 2024-05-24 - LyricsWidget Unnecessary Rebuilds
**Learning:** `LyricsWidget` was using a `Selector` that returned raw `progressMs` (which updates multiple times a second). This caused the entire widget (including large list views and translation overlays) to rebuild unnecessarily on every progress tick.
**Action:** When depending on high-frequency streams like audio playback progress, calculate the stable derived state (e.g., `currentLineIndex`) within the `selector` callback and return a value-equatable snapshot. This prevents unnecessary rebuilds.
