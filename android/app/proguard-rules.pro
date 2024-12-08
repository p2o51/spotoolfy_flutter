# Keep Spotify SDK classes
-keep class com.spotify.** { *; }
-keep interface com.spotify.** { *; }
-dontwarn com.spotify.**

# Keep Jackson classes
-keep class com.fasterxml.jackson.** { *; }
-keep interface com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# Keep AndroidX annotations
-keep class androidx.annotation.** { *; }
-dontwarn androidx.annotation.**

# Keep specific classes mentioned in the error
-keep class com.spotify.android.appremote.internal.SpotifyServiceBinder { *; }

# Additional rules for Spotify SDK
-keepattributes *Annotation*
-keepattributes Signature
-keep class * extends androidx.annotation.NonNull { *; }