# Flutter release 压缩规则
# Flutter 引擎与 Dart AOT 自身不受 R8 影响，这里主要为插件原生代码保留必要规则

# --- Flutter 官方建议 ---
# 保持 Flutter 引擎 JNI 入口
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- 本应用原生代码（通知桥/保活服务等经 MethodChannel 反射调用）---
-keep class com.Zeitlind.bill.** { *; }

# --- media-kit / ffmpeg 等含 JNI 的插件 ---
-keep class com.ryanheise.** { *; }
-keep class com.arthenica.** { *; }
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.**

# 音频服务（后台播放）
-keep class com.ryanheise.audioservice.** { *; }

# --- 通用防护：保留注解与原生接口 ---
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod
-dontwarn org.jetbrains.annotations.**

# --- R8 缺失类兜底（Flutter Play Store 分发/okhttp 可选依赖，
#     本应用不使用 Play 动态分发与 conscrypt，全部按忽略处理）---
-dontwarn com.google.android.play.core.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn org.bouncycastle.**
-dontwarn org.brotli.**

