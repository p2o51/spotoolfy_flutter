package com.gojyuplusone.spotoolfy.spotoolfy_flutter

import io.flutter.app.FlutterApplication
import com.google.android.material.color.DynamicColors

class SpotoolfyApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        DynamicColors.applyToActivitiesIfAvailable(this)
    }
} 