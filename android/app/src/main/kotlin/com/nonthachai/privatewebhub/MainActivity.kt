package com.nonthachai.privatewebhub

import android.os.SystemClock
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import android.view.MotionEvent
import android.view.KeyEvent
import android.view.InputDevice
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var remote: TvRemote? = null
    private var tvInput: TvInput? = null
    private var fullscreen = false

    override fun onStart() { super.onStart(); remote?.resume() }
    override fun onStop() { remote?.pause(); super.onStop() }
    override fun onDestroy() { tvInput?.dispose(); remote?.close(); super.onDestroy() }
    override fun onWindowFocusChanged(hasFocus: Boolean) { super.onWindowFocusChanged(hasFocus); if (hasFocus) tvInput?.refresh() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 731) remote?.permissionResponse(grantResults)
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (remote?.isTv == true && tvInput?.key(event) == true) return true
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv/remote")
        remote = TvRemote(this, channel)
        tvInput = TvInput(this, channel)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "inputState" -> result.success(tvInput?.state())
                    "fullscreen" -> { fullscreen = call.argument<Boolean>("active") == true; tvInput?.refresh(); result.success(null) }
                    "browser" -> { tvInput?.browserActive = call.argument<Boolean>("active") == true; result.success(null) }
                    "input" -> {
                        val action = call.argument<String>("action") ?: ""
                        if (action == "backFullscreen") {
                            if (fullscreen) {
                                dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
                                dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK))
                            }
                        } else if (action == "move") {
                            val dx = (call.argument<Number>("dx") ?: 0).toFloat()
                            val dy = (call.argument<Number>("dy") ?: 0).toFloat()
                            require(dx.isFinite() && dy.isFinite() && kotlin.math.abs(dx) <= 1 && kotlin.math.abs(dy) <= 1)
                            tvInput?.move(dx, dy)
                        } else if (tvInput?.perform(action) != true) {
                            val key = when (action) {
                                "up" -> KeyEvent.KEYCODE_DPAD_UP
                                "down" -> KeyEvent.KEYCODE_DPAD_DOWN
                                "left" -> KeyEvent.KEYCODE_DPAD_LEFT
                                "right" -> KeyEvent.KEYCODE_DPAD_RIGHT
                                "ok" -> KeyEvent.KEYCODE_DPAD_CENTER
                                "back" -> KeyEvent.KEYCODE_BACK
                                else -> error("Unsupported input")
                            }
                            dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, key))
                            dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, key))
                        }
                        result.success(null)
                    }
                    else -> remote!!.handle(call, result)
                }
            } catch (e: Exception) { result.error("input", e.message, null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv/app")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "version" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                        "updatePath" -> {
                            val directory = File(cacheDir, "updates").apply { mkdirs() }
                            result.success(File(directory, "update.apk").absolutePath)
                        }
                        "installUpdate" -> {
                            val apk = File(cacheDir, "updates/update.apk")
                            check(apk.isFile && apk.length() > 0) { "Downloaded APK is missing" }
                            val info = packageManager.getPackageArchiveInfo(apk.absolutePath, 0)
                            check(info?.packageName == packageName) { "APK does not match this app" }
                            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                                result.success(false)
                            } else {
                                val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
                                startActivity(Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                })
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("update", e.message, null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv/tap")
            .setMethodCallHandler { call, result ->
                if (call.method != "tap") return@setMethodCallHandler result.notImplemented()
                val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                val viewportWidth = call.argument<Double>("viewportWidth") ?: 0.0
                val web = findWebView(window.decorView)
                if (web == null || !viewportWidth.isFinite() || viewportWidth <= 0.0 || !x.isFinite() || !y.isFinite()) {
                    result.success(false)
                } else {
                    // Pages can be zoomed to fit, so scale CSS px by the real viewport ratio.
                    val scale = (web.width / viewportWidth).toFloat()
                    val px = x * scale
                    val py = y * scale
                    if (px < 0 || py < 0 || px >= web.width || py >= web.height) result.success(false)
                    else { tap(web, px, py); result.success(true) }
                }
            }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView && view.isShown) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findWebView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    // Real touch events keep isTrusted=true for pages that reject synthetic clicks.
    private fun tap(view: View, x: Float, y: Float) {
        val down = SystemClock.uptimeMillis()
        val properties = arrayOf(MotionEvent.PointerProperties().apply { id = 0; toolType = MotionEvent.TOOL_TYPE_FINGER })
        val coordinates = arrayOf(MotionEvent.PointerCoords().apply { this.x = x; this.y = y; pressure = 1f; size = 1f })
        val d = MotionEvent.obtain(down, down, MotionEvent.ACTION_DOWN, 1, properties, coordinates, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
        val u = MotionEvent.obtain(down, down + 60, MotionEvent.ACTION_UP, 1, properties, coordinates, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
        view.dispatchTouchEvent(d)
        view.postDelayed({
            view.dispatchTouchEvent(u)
            d.recycle()
            u.recycle()
        }, 60)
    }
}
