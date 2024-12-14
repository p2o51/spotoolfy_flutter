package com.gojyuplusone.spotoolfy.spotoolfy_flutter

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.util.Log
import android.app.WallpaperManager

/**
 * Utility object for handling dynamic colors based on system theme.
 */
object DynamicColorUtils {
    private const val TAG = "DynamicColorUtils"

    /**
     * Gets dynamic colors from the system theme.
     * @param context The application context
     * @return Pair of (background color, text color)
     */
    fun getDynamicColors(context: Context): Pair<Int, Int> {
        val resources = context.resources
        val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        val isDarkMode = uiMode == Configuration.UI_MODE_NIGHT_YES

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val wallpaperManager = WallpaperManager.getInstance(context)
                val colors = wallpaperManager.getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
                
                val primaryColor = if (isDarkMode) {
                    colors?.getSecondaryColor()?.toArgb()
                        ?: Color.parseColor("#1F1F1F")
                } else {
                    colors?.getPrimaryColor()?.toArgb()
                        ?: Color.parseColor("#E1E1E1")
                }

                Log.d(TAG, "Dynamic colors applied: primary=${String.format("#%06X", 0xFFFFFF and primaryColor)}")
                
                // 根据背景色的亮度选择文字颜色
                val onPrimaryColor = if (isDarkMode) {
                    Color.WHITE
                } else {
                    if (isColorLight(primaryColor)) Color.BLACK else Color.WHITE
                }

                Pair(primaryColor, onPrimaryColor)
            } catch (e: Exception) {
                Log.e(TAG, "Error getting dynamic colors", e)
                getDefaultColors(isDarkMode)
            }
        } else {
            Log.d(TAG, "Dynamic colors not available, using defaults")
            getDefaultColors(isDarkMode)
        }
    }

    /**
     * Gets default colors when dynamic colors are not available.
     * @param isDarkMode Whether the device is in dark mode
     * @return Pair of (background color, text color)
     */
    private fun getDefaultColors(isDarkMode: Boolean): Pair<Int, Int> {
        return if (isDarkMode) {
            Pair(Color.parseColor("#1F1F1F"), Color.WHITE)
        } else {
            Pair(Color.parseColor("#E1E1E1"), Color.BLACK)
        }
    }

    /**
     * Determines if a color is considered "light".
     * @param color The color to check
     * @return true if the color is light, false otherwise
     */
    private fun isColorLight(color: Int): Boolean {
        val darkness = 1 - (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color)) / 255
        return darkness < 0.5
    }
} 