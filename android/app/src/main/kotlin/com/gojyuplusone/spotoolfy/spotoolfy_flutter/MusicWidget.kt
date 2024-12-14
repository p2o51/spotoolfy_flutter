package com.gojyuplusone.spotoolfy.spotoolfy_flutter

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.os.Build
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition

class MusicWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_layout)
        
        // 获取动态颜色
        val (primaryColor, onPrimaryColor) = DynamicColorUtils.getDynamicColors(context)
        
        // 设置背景颜色
        views.setInt(R.id.widget_layout, "setBackgroundColor", primaryColor)
        
        // 设置文本颜色
        views.setTextColor(R.id.song_name, onPrimaryColor)
        views.setTextColor(R.id.artist_name, onPrimaryColor)
        
        // 设置按钮图标颜色
        views.setInt(R.id.previous_button, "setColorFilter", onPrimaryColor)
        views.setInt(R.id.play_pause_button, "setColorFilter", onPrimaryColor)
        views.setInt(R.id.next_button, "setColorFilter", onPrimaryColor)

        // 设置默认文本
        views.setTextViewText(R.id.song_name, "未在播放")
        views.setTextViewText(R.id.artist_name, "")
        
        // 设置默认播放按钮状态
        views.setImageViewResource(
            R.id.play_pause_button,
            android.R.drawable.ic_media_play
        )

        // 设置点击事件打开应用
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_layout, pendingIntent)

        // 设置播放/暂停按钮点击事件
        val playPauseIntent = Intent(context, MusicWidget::class.java).apply {
            action = "PLAY_PAUSE"
        }
        val playPausePendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            playPauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.play_pause_button, playPausePendingIntent)

        // 设置上一首按钮点击事件
        val previousIntent = Intent(context, MusicWidget::class.java).apply {
            action = "PREVIOUS"
        }
        val previousPendingIntent = PendingIntent.getBroadcast(
            context,
            1,
            previousIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.previous_button, previousPendingIntent)

        // 设置下一首按钮点击事件
        val nextIntent = Intent(context, MusicWidget::class.java).apply {
            action = "NEXT"
        }
        val nextPendingIntent = PendingIntent.getBroadcast(
            context,
            2,
            nextIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.next_button, nextPendingIntent)

        // 更新 widget
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    companion object {
        private var albumArtUrl: String? = null

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            songName: String? = null,
            artistName: String? = null,
            albumArtUrl: String? = null,
            isPlaying: Boolean = false
        ) {
            this.albumArtUrl = albumArtUrl
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            
            // 获取动态颜色
            val (primaryColor, onPrimaryColor) = DynamicColorUtils.getDynamicColors(context)
            
            // 设置背景颜色
            views.setInt(R.id.widget_layout, "setBackgroundColor", primaryColor)
            
            // 设置文本颜色
            views.setTextColor(R.id.song_name, onPrimaryColor)
            views.setTextColor(R.id.artist_name, onPrimaryColor)
            
            // 设置按钮图标颜色
            views.setInt(R.id.previous_button, "setColorFilter", onPrimaryColor)
            views.setInt(R.id.play_pause_button, "setColorFilter", onPrimaryColor)
            views.setInt(R.id.next_button, "setColorFilter", onPrimaryColor)
            
            // 更新文本
            views.setTextViewText(R.id.song_name, songName ?: "未在播放")
            views.setTextViewText(R.id.artist_name, artistName ?: "")
            
            // 设置播放/暂停按钮状态
            views.setImageViewResource(
                R.id.play_pause_button,
                if (isPlaying) R.drawable.ic_pause_filled else R.drawable.ic_play_filled
            )

            // 设置点击事件打开应用
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_layout, pendingIntent)

            // 设置播放/暂停按钮点击事件
            val playPauseIntent = Intent(context, MusicWidget::class.java).apply {
                action = "PLAY_PAUSE"
            }
            val playPausePendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                playPauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.play_pause_button, playPausePendingIntent)

            // 设置上一首按钮点击事件
            val previousIntent = Intent(context, MusicWidget::class.java).apply {
                action = "PREVIOUS"
            }
            val previousPendingIntent = PendingIntent.getBroadcast(
                context,
                1,
                previousIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.previous_button, previousPendingIntent)

            // 设置下一首按钮点击事件
            val nextIntent = Intent(context, MusicWidget::class.java).apply {
                action = "NEXT"
            }
            val nextPendingIntent = PendingIntent.getBroadcast(
                context,
                2,
                nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.next_button, nextPendingIntent)

            // 加载专辑封面
            if (!albumArtUrl.isNullOrEmpty()) {
                try {
                    Glide.with(context.applicationContext)
                        .asBitmap()
                        .load(albumArtUrl)
                        .into(object : CustomTarget<Bitmap>() {
                            override fun onResourceReady(
                                resource: Bitmap,
                                transition: Transition<in Bitmap>?
                            ) {
                                views.setImageViewBitmap(R.id.album_art, resource)
                                appWidgetManager.updateAppWidget(appWidgetId, views)
                            }

                            override fun onLoadCleared(placeholder: Drawable?) {
                                // 处理加载失败的情况
                            }
                        })
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            // 更新 widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        when (intent.action) {
            "PLAY_PAUSE", "PREVIOUS", "NEXT" -> {
                // 启动主活动并传递命令
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                    action = intent.action
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                context.startActivity(launchIntent)
            }
        }
    }
}