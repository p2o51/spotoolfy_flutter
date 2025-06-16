package com.gojyuplusone.spotoolfy.spotoolfy_flutter

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.annotation.NonNull
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            "PLAY_PAUSE" -> {
                methodChannel?.invokeMethod("togglePlayPause", null)
            }
            "PREVIOUS" -> {
                methodChannel?.invokeMethod("skipToPrevious", null)
            }
            "NEXT" -> {
                methodChannel?.invokeMethod("skipToNext", null)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Widget 控制通道
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gojyuplusone.spotoolfy/widget")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val songName = call.argument<String>("songName")
                    val artistName = call.argument<String>("artistName")
                    val albumArtUrl = call.argument<String>("albumArtUrl")
                    val isPlaying = call.argument<Boolean>("isPlaying")
                    
                    // 获取所有小部件ID并更新
                    val appWidgetManager = android.appwidget.AppWidgetManager.getInstance(this)
                    val appWidgetIds = appWidgetManager.getAppWidgetIds(
                        android.content.ComponentName(this, MusicWidget::class.java)
                    )
                    
                    // 更新所有小部件
                    for (appWidgetId in appWidgetIds) {
                        MusicWidget.updateAppWidget(
                            context = this,
                            appWidgetManager = appWidgetManager,
                            appWidgetId = appWidgetId,
                            songName = songName,
                            artistName = artistName,
                            albumArtUrl = albumArtUrl,
                            isPlaying = isPlaying ?: false
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        
        // 语言设置通道
        val languageChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "language_channel")
        languageChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAppLocale" -> {
                    try {
                        val languageTag = call.argument<String>("languageTag")
                        if (languageTag != null) {
                            val localeList = LocaleListCompat.forLanguageTags(languageTag)
                            AppCompatDelegate.setApplicationLocales(localeList)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Language tag is null", null)
                        }
                    } catch (e: Exception) {
                        result.error("SET_LOCALE_ERROR", e.message, null)
                    }
                }
                "clearAppLocale" -> {
                    try {
                        AppCompatDelegate.setApplicationLocales(LocaleListCompat.getEmptyLocaleList())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_LOCALE_ERROR", e.message, null)
                    }
                }
                "openSystemLanguageSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val intent = Intent(android.provider.Settings.ACTION_APP_LOCALE_SETTINGS).apply {
                                data = android.net.Uri.fromParts("package", packageName, null)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("UNSUPPORTED", "System language settings not supported on this Android version", null)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_ERROR", e.message, null)
                    }
                }
                "supportsSystemLanguageSettings" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                }
                else -> result.notImplemented()
            }
        }
    }
}
