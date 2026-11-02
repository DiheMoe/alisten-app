package moe.dihe.alisten

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        SharedTextChannel.attach(messenger)
        ClipboardChannel.attach(messenger, applicationContext)
        SystemSettingsChannel.attach(messenger, applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Activity 重建时，启动它的分享已经转交过 Dart。
        if (savedInstanceState == null) forwardSharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        forwardSharedText(intent)
    }

    private fun forwardSharedText(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_SEND) return
        // 从最近任务重新打开时，Activity 会再次收到启动它的分享。
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        intent.action = null
        if (!text.isNullOrBlank()) SharedTextChannel.send(text)
    }
}

// audio_service 缓存的引擎比 Activity 活得久，Dart 在引擎生命周期内只监听一次，
// 因此每个引擎只注册一次通道。Dart 开始监听前只保留最新一条分享。
private object SharedTextChannel : EventChannel.StreamHandler {
    private const val NAME = "moe.dihe.alisten/shared_text"

    private var messenger: BinaryMessenger? = null
    private var sink: EventChannel.EventSink? = null
    private var pending: String? = null

    fun attach(messenger: BinaryMessenger) {
        if (messenger === this.messenger) return
        this.messenger = messenger
        sink = null
        EventChannel(messenger, NAME).setStreamHandler(this)
    }

    fun send(text: String) {
        val sink = sink
        if (sink == null) pending = text else sink.success(text)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        pending?.let {
            pending = null
            events.success(it)
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}

private object ClipboardChannel {
    private const val NAME = "moe.dihe.alisten/clipboard"

    fun attach(messenger: BinaryMessenger, context: Context) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "primaryClipStamp" -> result.success(stamp(clipboard))
                "setSensitiveText" -> {
                    val text = call.argument<String>("text")
                    if (clipboard == null || text == null) {
                        result.success(false)
                    } else {
                        val clip = ClipData.newPlainText("", text)
                        // Android 13 起系统据此在剪贴板预览中隐藏内容；更早的版本没有
                        // 这个常量，改用相同的字符串键。
                        clip.description.extras = PersistableBundle().apply {
                            putBoolean(
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) ClipDescription.EXTRA_IS_SENSITIVE
                                else "android.content.extra.IS_SENSITIVE",
                                true,
                            )
                        }
                        clipboard.setPrimaryClip(clip)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // 只读剪贴板描述、不读内容：Android 12 起读取内容会弹出系统提示，Dart 据此
    // 只在剪贴板变化后才读取。
    private fun stamp(clipboard: ClipboardManager?): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val description = clipboard?.primaryClipDescription ?: return null
        return if (description.hasMimeType("text/*")) description.timestamp else null
    }
}

// 引擎比 Activity 活得久，用 applicationContext 启动以免持有已销毁的 Activity，
// 因此需要 FLAG_ACTIVITY_NEW_TASK。
private object SystemSettingsChannel {
    private const val NAME = "moe.dihe.alisten/system_settings"

    fun attach(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            if (call.method == "openNotificationSettings") {
                result.success(openNotificationSettings(context))
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings(context: Context): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null),
            )
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            false
        }
    }
}
