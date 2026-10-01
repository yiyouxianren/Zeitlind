package com.Zeitlind.bill

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodChannel

// import io.flutter.embedding.android.FlutterActivity

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val TAG = "PiliDebugBridge"
        private const val CHANNEL = "com.Zeitlind.bill/debug_events"

        private const val ACTION_PREFIX = "com.Zeitlind.bill.DEBUG_"

        // 下载进度通知
        private const val DL_NOTIF_CHANNEL = "com.Zeitlind.bill.download"
        private const val DL_NOTIF_ID = 91001
    }

    private var eventSink: EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var receiver: BroadcastReceiver? = null

    override fun onPause() {
        super.onPause()
        Log.d("PiliLifecycle", "Activity onPause @ ${System.currentTimeMillis()}")
    }

    override fun onResume() {
        super.onResume()
        Log.d("PiliLifecycle", "Activity onResume START @ ${System.currentTimeMillis()}")
    }

    /**
     * 常驻主线程心跳：500ms 一拍。检测到阻塞 >1300ms 时转储主线程栈。
     * 仅 debug 构建启用（release 不引入开销）。
     */
    private var heartbeatStarted = false
    private fun startHeartbeat() {
        if (heartbeatStarted || !BuildConfig.DEBUG) return
        heartbeatStarted = true
        Thread {
            var last = System.currentTimeMillis()
            while (true) {
                Thread.sleep(500)
                mainHandler.post {
                    val now = System.currentTimeMillis()
                    val gap = now - last
                    last = now
                    if (gap > 1300) {
                        Log.w("PiliLifecycle", "MAIN THREAD BLOCKED ${gap}ms")
                        val stacks = Thread.getAllStackTraces()
                        val main = stacks.entries.firstOrNull {
                            it.key.name == "main" && it.key.state == Thread.State.RUNNABLE
                        }?.value
                        if (main != null) {
                            for (frame in main.take(40)) {
                                Log.w("PiliLifecycle", "  at $frame")
                            }
                        } else {
                            Log.w("PiliLifecycle", "  (main thread not RUNNABLE; all states below)")
                            for ((t, s) in stacks) {
                                if (t.name == "main") {
                                    for (frame in s.take(20)) {
                                        Log.w("PiliLifecycle", "  [${t.state}] at $frame")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }.start()
    }

    override fun onStop() {
        super.onStop()
        Log.d("PiliLifecycle", "Activity onStop @ ${System.currentTimeMillis()}")
    }

    override fun onStart() {
        super.onStart()
        Log.d("PiliLifecycle", "Activity onStart @ ${System.currentTimeMillis()}")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventSink) {
                eventSink = events
                Log.d(TAG, "stream listening")
                if (BuildConfig.DEBUG) {
                    // debug 构建发送就绪事件，Dart 侧用于确认链路
                    events.success(mapOf("cmd" to "READY"))
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        registerDebugReceiver()
        registerDownloadNotificationChannel(flutterEngine)
        startHeartbeat()
    }

    /**
     * 下载进度通知：
     *   showProgress(title, text, progress 0-100) —— 更新进度条通知
     *   done(title, text) —— 完成（移除进度条，稍后自动消失或点按清除）
     *   cancel() —— 移除通知
     */
    private fun registerDownloadNotificationChannel(flutterEngine: FlutterEngine) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                DL_NOTIF_CHANNEL,
                "下载进度",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "视频下载进度通知"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.Zeitlind.bill/download_notification"
        ).setMethodCallHandler { call, result ->
            mainHandler.post {
                try {
                    when (call.method) {
                        "showProgress" -> {
                            val title = call.argument<String>("title") ?: "批量下载"
                            val text = call.argument<String>("text") ?: ""
                            val progress = (call.argument<Int>("progress") ?: 0)
                                .coerceIn(0, 100)
                            val indeterminate = call.argument<Boolean>("indeterminate") ?: false
                            val n = NotificationCompat.Builder(this, DL_NOTIF_CHANNEL)
                                .setSmallIcon(resources.getIdentifier(
                                    "ic_notification_icon", "drawable", packageName))
                                .setContentTitle(title)
                                .setContentText(text)
                                .setOnlyAlertOnce(true)
                                .setOngoing(true)
                                .setSilent(true)
                                .setProgress(100, progress, indeterminate)
                                .build()
                            nm.notify(DL_NOTIF_ID, n)
                            result.success(true)
                        }
                        "done" -> {
                            val title = call.argument<String>("title") ?: "下载完成"
                            val text = call.argument<String>("text") ?: ""
                            val n = NotificationCompat.Builder(this, DL_NOTIF_CHANNEL)
                                .setSmallIcon(resources.getIdentifier(
                                    "ic_notification_icon", "drawable", packageName))
                                .setContentTitle(title)
                                .setContentText(text)
                                .setOnlyAlertOnce(true)
                                .setAutoCancel(true)
                                .build()
                            nm.notify(DL_NOTIF_ID, n)
                            result.success(true)
                        }
                        "cancel" -> {
                            nm.cancel(DL_NOTIF_ID)
                            result.success(true)
                        }
                        "startKeepAlive" -> {
                            // 下载保活前台服务（前台通知 + WakeLock）
                            val intent = Intent(this, DownloadForegroundService::class.java)
                            intent.action = DownloadForegroundService.ACTION_START
                            try {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                    startForegroundService(intent)
                                } else {
                                    startService(intent)
                                }
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SVC_ERR", e.message, null)
                            }
                        }
                        "stopKeepAlive" -> {
                            val intent = Intent(this, DownloadForegroundService::class.java)
                            intent.action = DownloadForegroundService.ACTION_STOP
                            try {
                                startService(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SVC_ERR", e.message, null)
                            }
                        }
                        "openBatterySettings" -> {
                            // 跳转应用电池优化设置（华为：受保护应用/启动管理）
                            try {
                                val intent = Intent()
                                intent.action = android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SVC_ERR", e.message, null)
                            }
                        }
                        "isIgnoringBatteryOptimizations" -> {
                            val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                            val pkg = packageName
                            val ignoring = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                                pm.isIgnoringBatteryOptimizations(pkg)
                            } else true
                            result.success(ignoring)
                        }
                        "getPowerSavePolicy" -> {
                            // 华为 EMUI/HarmonyOS 后台省电策略：
                            // 通过 HwBatteryManager 读取当前应用的启动管理状态。
                            // 返回 "unrestricted" / "restricted" / "unknown"
                            result.success(getHuaweiPowerSavePolicy())
                        }
                        "openHuaweiAppLaunchSettings" -> {
                            // 华为「应用启动管理」页面：
                            // 关闭「自动管理」后即可手动设为「允许后台活动」
                            try {
                                val intent = Intent()
                                intent.setClassName(
                                    "com.huawei.systemmanager",
                                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                                )
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                // 兜底：系统电池优化页
                                try {
                                    val fallback = Intent()
                                    fallback.action = android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                    startActivity(fallback)
                                    result.success(true)
                                } catch (e2: Exception) {
                                    result.error("SVC_ERR", e2.message, null)
                                }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NOTIF_ERR", e.message, null)
                }
            }
        }
    }

    /**
     * 华为后台省电策略查询（EMUI 14 / HarmonyOS）。
     * 实现：HwBatteryManager 没有公开 API；用反射读 systemmanager 的
     * StartupNormalAppListActivity 对应 ContentProvider 不可行（无权限），
     * 因此采用两个信号的组合判断：
     *   1. PowerManager.isIgnoringBatteryOptimizations（系统白名单）
     *   2. HwSystemManager 反射 getPowerSaveCheckResult（部分版本可用）
     * 任一显示"受限"则返回 restricted；无法判定时返回 unknown（由 Dart
     * 侧退回到标准电池优化引导）。
     */
    private fun getHuaweiPowerSavePolicy(): String {
        val pkg = packageName
        // 1) 标准电池优化白名单
        val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val ignoringOpt = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            try { pm.isIgnoringBatteryOptimizations(pkg) } catch (_: Exception) { true }
        } else true

        // 2) 华为反射查询（EMUI 的 PowerGenie / StartupManager 状态）
        var hwUnrestricted: Boolean? = null
        if (!ignoringOpt) {
            // 白名单都没进，基本可判定受限；仍尝试华为接口确认
            hwUnrestricted = tryHwQuery(pkg)
        } else {
            hwUnrestricted = tryHwQuery(pkg) ?: true
        }

        return when {
            hwUnrestricted == false -> "restricted"
            hwUnrestricted == true && ignoringOpt -> "unrestricted"
            else -> "unknown"
        }
    }

    /** 反射查询华为 systemmanager 的应用启动状态；失败返回 null。 */
    private fun tryHwQuery(pkg: String): Boolean? {
        return try {
            // HwSystemManager 暴露的静态工具类（EMUI 9-14 均有）
            val clz = Class.forName("com.huawei.systemmanager.HwSystemManager")
            // 尝试常见方法签名；不存在则返回 null 走 unknown 分支
            for (name in listOf("getAppControlType", "isStartAllowed", "getPowerSaveStatus")) {
                try {
                    val m = clz.getDeclaredMethod(name, String::class.java)
                    m.isAccessible = true
                    val r = m.invoke(null, pkg)
                    when (r) {
                        is Int -> if (r != 0) return false  // 0=智能/允许
                        is Boolean -> if (!r) return false
                        is String -> if (r.contains("restrict", true)) return false
                    }
                } catch (_: Exception) { /* 该签名不存在，试下一个 */ }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun registerDebugReceiver() {
        if (!BuildConfig.DEBUG) {
            Log.i(TAG, "release build: debug receiver disabled")
            return
        }
        if (receiver != null) return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.action ?: return
                if (!action.startsWith(ACTION_PREFIX)) return
                val cmd = action.removePrefix(ACTION_PREFIX)

                // 通用 extras 转发：支持 --ei/--es/--ez 注入的任意参数
                val payload = mutableMapOf<String, Any?>("cmd" to cmd)
                intent.extras?.let { extras: Bundle ->
                    for (key in extras.keySet()) {
                        when (val v = extras.get(key)) {
                            null -> payload[key] = null
                            is Int, is Long, is String, is Boolean,
                            is Double, is Float -> payload[key] = v
                            else -> payload[key] = v.toString()
                        }
                    }
                }
                Log.d(TAG, "forward cmd=$cmd payload=$payload")
                sendToFlutter(payload)
            }
        }
        // 显式枚举命令注册：部分 ROM（如 EMUI）对通配 action 匹配不可靠，
        // 显式 action 是最稳妥的方式。新增命令时在此列表同步添加。
        val filter = IntentFilter()
        listOf(
            "PING", "GET_AUDIO_MODE", "SET_AUDIO_MODE", "GOTO_LIVE_ROOM",
            "GOTO_VIDEO", "GET_COMMENTS", "GET_DANMAKU", "GET_LIVE_DANMAKU",
            "GET_CURRENT_STATE", "GET_UI_TREE", "TAP_NODE", "SHOW_CONTROLS",
            "SET_PLAYBACK_SPEED", "GOTO_PAGE", "SET_SIMPLE_MODE"
        ).forEach { cmd -> filter.addAction("$ACTION_PREFIX$cmd") }
        try {
            registerReceiver(receiver, filter)
            Log.d(TAG, "debug receiver registered (explicit actions, ${filter.countActions()} commands)")
        } catch (e: Exception) {
            Log.e(TAG, "debug receiver registration failed: ${e.message}")
        }
    }

    private fun sendToFlutter(payload: Map<String, Any?>) {
        val sink = eventSink
        if (sink != null) {
            mainHandler.post {
                sink.success(payload)
            }
        } else {
            Log.w(TAG, "eventSink null, dropping: $payload")
        }
    }

    override fun onDestroy() {
        receiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        receiver = null
        super.onDestroy()
    }
}
