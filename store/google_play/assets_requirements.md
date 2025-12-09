# Google Play Store Assets Requirements - Spotoolfy

This document outlines the required graphic assets for Google Play Console submission.

---

## Required Assets

### 1. App Icon (High-res)
| Specification | Requirement |
|---------------|-------------|
| Dimensions | 512 x 512 px |
| Format | PNG (32-bit with alpha) |
| File size | Max 1 MB |
| Notes | Must match the app's launcher icon |

**Current location:** `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`

**Action needed:** Export a 512x512 version of the icon

---

### 2. Feature Graphic
| Specification | Requirement |
|---------------|-------------|
| Dimensions | 1024 x 500 px |
| Format | PNG or JPG (24-bit, no alpha) |
| File size | Max 1 MB |
| Notes | Displayed at top of store listing |

**Suggested design:**
- Background: Gradient with app's primary colors
- Elements: App logo, music visualization graphics
- Text: "Spotoolfy" with tagline "Smart Lyrics Player"
- Style: Material Design 3 aesthetic

---

### 3. Phone Screenshots (Required)
| Specification | Requirement |
|---------------|-------------|
| Minimum | 2 screenshots |
| Maximum | 8 screenshots |
| Dimensions | Min 320px, Max 3840px (any side) |
| Aspect ratio | 16:9 or 9:16 |
| Format | PNG or JPG (24-bit, no alpha) |
| File size | Max 8 MB each |

**Recommended screenshots (in order):**

1. **Now Playing Screen**
   - Show album artwork with dynamic theme
   - Playback controls visible
   - Caption: "Beautiful Now Playing with Dynamic Themes"

2. **Lyrics Display**
   - Synchronized lyrics view
   - Highlight current line
   - Caption: "Real-time Synchronized Lyrics"

3. **Lyrics Translation**
   - Show original + translated lyrics
   - Caption: "AI-Powered Lyrics Translation"

4. **Personal Notes**
   - Notes list or note editing screen
   - Caption: "Add Personal Notes to Your Music"

5. **Music Library**
   - Library view with playlists/albums
   - Caption: "Access Your Spotify Library"

6. **Album Details**
   - Album page with track ratings
   - Caption: "Rate and Review Albums"

7. **AI Insights**
   - Generated music insights
   - Caption: "Discover Your Music Personality"

8. **Settings**
   - Settings page showing customization options
   - Caption: "Customize Your Experience"

---

### 4. Tablet Screenshots (Optional but Recommended)
| Specification | Requirement |
|---------------|-------------|
| Minimum | 0 (optional) |
| Maximum | 8 screenshots |
| Dimensions | 7-inch: 1024 x 500 px minimum |
| Aspect ratio | 16:9 |

---

## Screenshot Best Practices

### Do's
- Use actual app screenshots (not mockups)
- Show real content (music, lyrics, notes)
- Use high contrast for readability
- Include status bar and navigation
- Show different features in each screenshot

### Don'ts
- Don't include device frames (Google adds these)
- Don't use blurry or low-quality images
- Don't show copyrighted content prominently
- Don't include pricing or promotional text
- Don't show placeholder/test data

---

## Screenshot Generation Commands

### Android (using ADB)
```bash
# Connect device and enable USB debugging
adb shell screencap -p /sdcard/screenshot.png
adb pull /sdcard/screenshot.png ~/Desktop/
```

### Flutter
```bash
# Use integration_test with screenshots
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart
```

---

## Recommended Screenshot Dimensions

| Device Type | Recommended Size |
|-------------|------------------|
| Phone (Portrait) | 1080 x 1920 px (9:16) |
| Phone (Landscape) | 1920 x 1080 px (16:9) |
| 7-inch Tablet | 1200 x 1920 px |
| 10-inch Tablet | 1600 x 2560 px |

---

## Promotional Assets (Optional)

### Promo Video
| Specification | Requirement |
|---------------|-------------|
| URL | YouTube video link |
| Length | 30 seconds - 2 minutes |
| Content | App walkthrough and features |

### TV Banner (if applicable)
| Specification | Requirement |
|---------------|-------------|
| Dimensions | 1280 x 720 px |
| Format | PNG or JPG (24-bit, no alpha) |

---

## Asset Checklist

- [ ] App icon (512x512 PNG)
- [ ] Feature graphic (1024x500 PNG/JPG)
- [ ] Phone screenshot 1: Now Playing
- [ ] Phone screenshot 2: Lyrics
- [ ] Phone screenshot 3: Translation
- [ ] Phone screenshot 4: Notes
- [ ] Phone screenshot 5: Library
- [ ] Phone screenshot 6: Album Details
- [ ] Phone screenshot 7: AI Insights
- [ ] Phone screenshot 8: Settings
- [ ] (Optional) Tablet screenshots
- [ ] (Optional) Promo video

---

## Asset Storage

Create and store assets in:
```
store/google_play/assets/
├── icon/
│   └── app_icon_512.png
├── feature_graphic/
│   └── feature_graphic_1024x500.png
├── screenshots/
│   ├── phone/
│   │   ├── 01_now_playing.png
│   │   ├── 02_lyrics.png
│   │   ├── 03_translation.png
│   │   ├── 04_notes.png
│   │   ├── 05_library.png
│   │   ├── 06_album.png
│   │   ├── 07_insights.png
│   │   └── 08_settings.png
│   └── tablet/
│       └── ...
└── promo/
    └── promo_video_thumbnail.png
```

---

## Notes

1. **Copyright considerations**: Ensure album artwork in screenshots is either:
   - From royalty-free sources
   - Blurred/anonymized
   - Your own test content

2. **Localization**: Consider creating separate screenshot sets for different languages if targeting multiple regions.

3. **A/B testing**: Google Play allows A/B testing different screenshots. Consider creating variations.
