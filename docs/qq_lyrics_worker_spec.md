# QQ Lyrics Worker Specification

This document explains everything the new QQ lyrics worker needs so that the Flutter web build can keep using QQ Music lyrics without trying to mimic QQ's browser fingerprint locally. Hand this spec to the worker-owning agent and they have all of the inputs, outputs, and edge cases that `lib/services/lyrics/qq_provider.dart` currently handles.

---

## 1. Background & Goals
- The mobile/desktop builds call QQ Music directly via `QQProvider` (`lib/services/lyrics/qq_provider.dart`), but browsers cannot set the required `referer`/`user-agent` headers or bypass QQ's CORS policy.
- The worker must live outside the browser sandbox (Cloudflare Worker, Vercel Edge Function, etc.) and expose a tiny HTTP API that the Flutter web app can call.
- Two capabilities are required:
  1. Search QQ Music to obtain a `songmid`.
  2. Fetch the lyric payload (primary, translated, and romanized text) for that `songmid`.
- The worker does **not** need to duplicate our local caching layer (that still sits in `LyricsService`); it only needs to faithfully proxy QQ.

---

## 2. Upstream QQ API Details (from `qq_provider.dart`)

### 2.1 Song Search
- **Endpoint:** `https://c.y.qq.com/soso/fcgi-bin/client_search_cp`
- **Method:** `GET`
- **Query params:**
  - `w` – search keyword (`"$title $artist"`; artist can be empty)
  - `p=1` – first page
  - `n=3` – fetch up to three matches (we only use the first)
  - `format=json`
- **Headers (required or QQ returns 403/CORS errors):**
  - `referer: https://y.qq.com/`
  - `user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36`
- **Timeout:** 10 seconds. Treat timeouts as retryable failures.
- **Response shape (trimmed):**
  ```json
  {
    "data": {
      "song": {
        "list": [
          {
            "songmid": "003rJSwb1Y9P7v",
            "songname": "你瞒我瞒",
            "singer": [{ "name": "陈柏宇" }]
          }
        ]
      }
    }
  }
  ```
- The worker must return at least `{ songId, title, artist }`. (`songId` → `songmid`.)

### 2.2 Lyric Fetch
- **Primary endpoint:** `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg`
- **Backup endpoint:** `https://u6.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg`
- **Method:** `GET`
- **Query params:**
  - `songmid=<songId from search>`
  - `format=json`
  - `nobase64=1` (gives plain text lyrics so we avoid base64 decoding)
- **Headers:** same as the search endpoint.
- **Timeout:** 10 seconds.
- **Failover logic:** if QQ returns HTTP 403 or 429, flip to the backup domain and retry once.
- **Response fields of interest (see `QQLyricPayload` in the code):**
  - `lyric` – primary lyric (may already include `[mm:ss.xx]` timestamps)
  - `trans` – translated lyric (may be empty)
  - `klyric` – romanized lyric. QQ sends either a string or `{ "lyric": "<text>" }`.
  - The entire JSON blob should be preserved for debugging.

### 2.3 Normalization expectations
- After `fetch`, the app runs `LyricProvider.normalizeLyric` (`lib/services/lyrics/lyric_provider.dart`):
  - HTML entity decode (via `HtmlUnescape`)
  - Replace Windows line endings with `\n`
  - Trim repeated blank lines and surrounding whitespace
- The worker can return raw QQ payloads and let the Flutter client normalize, **or** normalize server-side as long as we keep the same behavior. Specify what you decided in the response JSON.

---

## 3. Worker API Contract

> If you need a different shape for your runtime, feel free to adjust, but this contract is the easiest drop-in replacement for the existing provider.

### 3.1 `POST /qq/search`
- **Request body:**
  ```json
  {
    "title": "Bohemian Rhapsody",
    "artist": "Queen",
    "limit": 3 // optional override, defaults to 3
  }
  ```
- **Response (200):**
  ```json
  {
    "matches": [
      {
        "songId": "002123456",
        "title": "Bohemian Rhapsody",
        "artist": "Queen"
      }
    ],
    "raw": { ...original QQ payload... }
  }
  ```
- **Error statuses:**
  - `404` when QQ returns no list entries.
  - `504` for timeouts.
  - `5xx` for QQ/network failures (include `error` and `upstreamStatus` fields).

### 3.2 `POST /qq/lyrics`
- **Request body:**
  ```json
  {
    "songId": "002123456",
    "includeTranslation": true,
    "includeRomanized": true
  }
  ```
- **Response (200):**
  ```json
  {
    "songId": "002123456",
    "lyric": "[00:00.00] ...",
    "translatedLyric": "[00:00.00] ...",        // optional
    "romanizedLyric": "[00:00.00] ...",         // optional
    "raw": { ...complete QQ JSON... },
    "sourceDomain": "c.y.qq.com",
    "fetchedAt": "2024-05-31T09:12:33Z"
  }
  ```
- If no lyric-like content exists, return `404` so the Flutter side can fall back to NetEase/LRCLIB.

### 3.3 Combined Shortcut (optional)
- You may add `POST /qq/resolveLyric` that accepts `{ title, artist }` and performs search + lyric fetch server-side, returning `{ provider: "qq", lyric: "<normalized text>" }`. This mirrors `LyricProvider.getLyric`.

---

## 4. Behavioral Requirements
1. **Time limits & retries**
   - Search and lyric fetch each have a 10-second cap. Apply a single retry when the failure is timeout or HTTP 5xx.
2. **Header spoofing**
   - Always send the two headers listed above. Do **not** forward browser headers; some of them trigger QQ bot detection.
3. **Domain failover**
   - Only switch to `u6.y.qq.com` when QQ replies with 403 or 429. If both domains fail, bubble up the last error.
4. **Response normalization (if done server-side)**
   - Mirror `normalizeLyric` behavior: HTML unescape, collapse blank lines, trim trailing whitespace.
5. **Logging & metrics**
   - Log: query keyword, upstream domain, HTTP status, whether lyric contained timestamps (optional call to a lightweight regex, e.g., `\[\d{1,2}:\d{2}`).
6. **Rate limiting**
   - QQ can soft-ban IPs. Implement a simple token bucket (e.g., 30 lyric fetches/min) or integrate with Cloudflare KV/Upstash Redis if needed.
7. **Security**
   - Add a shared secret header or signed token so random clients cannot hammer the worker.

---

## 5. Mapping Back to Flutter
- `LyricsService` (`lib/services/lyrics_service.dart`) still orchestrates provider fallbacks and caching by `trackId`.
- To plug the worker in, we can create a `RemoteQQProvider` that calls these worker endpoints instead of QQ directly but still exposes the same `LyricProvider` interface (`search`, `fetchLyric`, `name => 'qq'`).
- Keep the response schema identical (`SongMatch`, normalized lyric string) so no other part of the app changes.

---

## 6. Testing & Verification
1. **Unit tests (worker side)**
   - Mock `fetch`/HTTP client to cover success, timeout, 403→fallback, invalid JSON.
2. **Integration smoke**
   - Run `curl` against `/qq/resolveLyric` for a known song and confirm you get synchronized LRC lines (look for `[mm:ss.xx]`).
3. **Flutter regression**
   - Locally run `dart run tool/qq_lyric_probe.dart "Song" "Artist"` to capture the baseline lyric.
   - Point the Flutter web build to the worker and ensure the returned lyric matches (within normalization differences).

---

## 7. Reference Code Paths
- `lib/services/lyrics/qq_provider.dart` — canonical behavior to mimic.
- `lib/services/lyrics/lyric_provider.dart` — normalization and provider contract.
- `tool/qq_lyric_probe.dart` — CLI harness that exercises the same flow and is handy for comparing worker output.

Hand this spec to the worker agent and they can build a drop-in QQ lyrics proxy without reverse-engineering the Flutter codebase.
