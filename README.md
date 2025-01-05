# Spotoolfy Flutter

A Flutter application that enhances your Spotify experience with additional features.

## Features

- 🎵 Real-time Spotify playback control
- 💭 Add personal notes to tracks
- ❤️ Save/unsave tracks to your library
- 🔄 Auto-refresh current playing track
- 🎨 Material 3 design with dynamic theming for album art

## APK & TestFlight
Please note that you need to contact me to request Spotify API permissions before testing (currently in developer mode, registration is required).
APK： https://drive.google.com/file/d/136C8Sv1pQ0cOTGabpDSkCxUhv8T_CKxX/view?usp=sharing
TestFlight：https://testflight.apple.com/join/h2GR2Gbf

## Recently Roadmap

Spotoolfy 1.1
New Year, New Version.
### API Experience
- Optimize the refresh timing of songs.
- Support Spotify Connect audio display and playback
### UI & Naming Reconstruction
- Single line scrolling display of song name and artist
- Rebuild user page, add lyrics switch and developer contact information
- Add traditional Chinese conversion to lyrics page
- Spotify API compliance, rename and add "return to Spotify" button

## Configuration

### Spotify API Credentials
1. Copy `lib/config/secrets.example.dart` to `lib/config/secrets.dart`
2. Replace the placeholder values in `secrets.dart` with your Spotify API credentials:
   ```dart
   class SpotifySecrets {
     static const String clientId = 'your_client_id_here';
     static const String clientSecret = 'your_client_secret_here';
   }
   ```
3. Never commit `secrets.dart` to version control

