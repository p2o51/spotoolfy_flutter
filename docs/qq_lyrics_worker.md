# QQ Lyrics Proxy Worker — Integration Guide

This document captures the exact contract our Flutter web build expects from the Cloudflare Worker hosted at `https://lyrics.gojyuplus.com`. Share it with the worker-focused agent so they can implement or update the proxy independently from the mobile (native) lyric flow.

## Background

- Mobile builds can masquerade as QQ Music clients and talk to the public APIs directly, but browsers cannot set the required headers (`referer`, `user-agent`) and are blocked by QQ Music's CORS policy.
- We now route **all Flutter web lyric lookups** through a Cloudflare Worker that forwards requests to QQ Music, adds the proper headers, and returns normalized JSON that mirrors our `LyricProvider` expectations.
- Native builds keep using the existing direct `QQProvider`, so the worker must remain backwards-compatible with the schema described below.

## Required Endpoints

The Worker exposes three POST endpoints under the `/qq` namespace. Each response must include `Access-Control-Allow-Origin: *` and `Access-Control-Allow-Headers: *` (or echo the request origin) so browsers can consume it.

### 1. `/qq/search`

Searches QQ Music for a song by title/artist.

**Request Body**
```json
{
  "title": "Bohemian Rhapsody",
  "artist": "Queen",
  "limit": 3
}
```

**Response Body**
```json
{
  "matches": [
    {
      "songId": "002123456",
      "title": "Bohemian Rhapsody",
      "artist": "Queen"
    }
  ],
  "raw": { "/* original QQ API response */": "..." }
}
```

**Status Codes**

| Code | Meaning | Client handling |
| ---- | ------- | --------------- |
| 200  | Results returned | Use the first result |
| 400  | Missing/invalid `title` | Surface error |
| 404  | No match | Treated as null result |
| 5xx/504 | Worker/upstream failure | Retry once client-side |

### 2. `/qq/lyrics`

Fetches a lyric payload for a QQ `songId`.

**Request Body**
```json
{
  "songId": "002123456",
  "includeTranslation": true,
  "includeRomanized": true
}
```

**Response Body**
```json
{
  "songId": "002123456",
  "lyric": "[00:00.00] Lyrics text...",
  "translatedLyric": "[00:00.00] Translated lyrics...",
  "romanizedLyric": "[00:00.00] Romanized lyrics...",
  "hasTimestamps": true,
  "sourceDomain": "c.y.qq.com",
  "fetchedAt": "2024-05-31T09:12:33Z",
  "raw": { "/* original QQ API response */": "..." }
}
```

**Status Codes**

- `200`: Lyrics returned (primary `lyric` field is mandatory even if translations are absent)
- `404`: No lyrics available for the song
- `5xx/504`: Worker/upstream failure

### 3. `/qq/resolveLyric` (preferred)

Performs search + lyric fetch in a single hop. Our Flutter web provider calls this endpoint first and only falls back to `/qq/search` + `/qq/lyrics` if it fails.

**Request Body**
```json
{
  "title": "Bohemian Rhapsody",
  "artist": "Queen",
  "includeTranslation": true,
  "includeRomanized": true
}
```

**Response Body**
```json
{
  "provider": "qq",
  "songId": "002123456",
  "title": "Bohemian Rhapsody",
  "artist": "Queen",
  "lyric": "[00:00.00] Lyrics text...",
  "translatedLyric": "[00:00.00] Translated lyrics...",
  "romanizedLyric": "[00:00.00] Romanized lyrics...",
  "hasTimestamps": true,
  "sourceDomain": "c.y.qq.com",
  "fetchedAt": "2024-05-31T09:12:33Z",
  "raw": {
    "search": { "/* search API response */": "..." },
    "lyrics": { "/* lyrics API response */": "..." }
  }
}
```

**Status Codes**

- `200`: Success
- `400`: Missing/invalid `title`
- `404`: Either search or lyric lookup returned nothing
- `5xx/504`: Worker/upstream failure

## Functional Requirements

- **Header spoofing**: Worker must add `referer: https://y.qq.com/` and a desktop `user-agent` string for every QQ request. QQ blocks browsers without these.
- **CORS**: Always send permissive CORS headers (`Access-Control-Allow-Origin`, `Access-Control-Allow-Headers`, `Access-Control-Allow-Methods`).
- **Retry & failover**:
  - Search: retry once on timeout or QQ 5xx.
  - Lyric fetch: fail over between `https://c.y.qq.com` and `https://u6.y.qq.com` on `403`/`429`.
  - Timeouts: 10 seconds per upstream call.
- **Normalization**: Return lyrics already decoded from Base64/HTML entities, convert CRLF to LF, collapse >2 blank lines, trim surrounding whitespace—this matches the native `LyricProvider.normalizeLyric`.
- **Error payloads**: Include `message` and `details` fields for non-200 responses to help UI logging.
- **Authentication (optional)**: If `AUTH_SECRET` is set, require `Authorization: Bearer <secret>`; otherwise allow anonymous calls.

## Deployment Checklist

1. Use Node.js 18+, Wrangler CLI, and a Cloudflare account.
2. Slots:
   - `npm run dev` → local testing at `http://localhost:8787`.
   - `npm run deploy` → pushes to `https://qq-lyrics-proxy.<subdomain>.workers.dev`.
   - Bind a custom domain (`lyrics.gojyuplus.com`) once stable.
3. Store private secrets via `wrangler secret put AUTH_SECRET`; never commit plain secrets.
4. Add automated tests (e.g., Vitest) covering each endpoint with mocked QQ responses.

## How Flutter Web Uses the Worker

- `lib/services/lyrics/qq_provider_web.dart` posts to `/qq/resolveLyric` first. If it gets a `200` with a non-empty `lyric`, it normalizes and returns it to the UI.
- When `/qq/resolveLyric` fails, the provider falls back to `/qq/search` + `/qq/lyrics`.
- Responses must stay small (deflate large `raw` payloads if possible) because they are cached client-side for 30 days.
- Mobile builds bypass the worker entirely by compiling `qq_provider_mobile.dart`, so no behavior change is expected outside the web target.

Please keep this contract stable; any breaking change will require a Flutter update.
