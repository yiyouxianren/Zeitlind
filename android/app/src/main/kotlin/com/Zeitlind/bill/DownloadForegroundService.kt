package com.Zeitlind.bill

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * 下载保活前台服务：
 * - 前台通知（复用「下载进度」渠道）防止进程被冻结/网络被断
 * - PARTIAL_WAKE_LOCK 保持 CPU 运行（Dart Timer/Dio 下载继续）
 * - startForeground(STOP_FOREGROUND_REMOVE) 停止时移除通知
 */
class DownloadForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "com.Zeitlind.bill.download"
        const val NOTIFICATION_ID = 91002
        const val ACTION_START = "com.Zeitlind.bill.download.START"
        const val ACTION_STOP = "com.Zeitlind.bill.download.STOP"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "下载进度",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "视频下载进度通知"
                    setShowBadge(false)
                }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseWake()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                // startForeground（Android 14 必须在 5s 内调用）
                startForeground(NOTIFICATION_ID, buildNotification("下载进行中"))
                acquireWake()
            }
        }
        return START_STICKY
    }

    private fun acquireWake() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Zeitlind:download")
                .apply { setReferenceCounted(false); acquire(2 * 60 * 60 * 1000L) }
        } else if (wakeLock?.isHeld == false) {
            wakeLock?.acquire(2 * 60 * 60 * 1000L)
        }
    }

    private fun releaseWake() {
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wakeLock = null
    }

    private fun buildNotification(text: String): Notification {
        val icon = resources.getIdentifier("ic_notification_icon", "drawable", packageName)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(if (icon != 0) icon else android.R.drawable.stat_sys_download)
            .setContentTitle("正在下载")
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build()
    }

    override fun onDestroy() {
        releaseWake()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
