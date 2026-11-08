package com.nonthachai.privatewebhub

import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mv/tap")
            .setMethodCallHandler { call, result ->
                if (call.method != "tap") return@setMethodCallHandler result.notImplemented()
                val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                val viewportWidth = call.argument<Double>("viewportWidth") ?: 0.0
                val web = findWebView(window.decorView)
                if (web == null || viewportWidth <= 0.0) {
                    result.success(false)
                } else {
                    // Pages can be zoomed to fit, so scale CSS px by the real viewport ratio.
                    val scale = (web.width / viewportWidth).toFloat()
                    tap(web, x * scale, y * scale)
                    result.success(true)
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
        val d = MotionEvent.obtain(down, down, MotionEvent.ACTION_DOWN, x, y, 0)
        val u = MotionEvent.obtain(down, down + 60, MotionEvent.ACTION_UP, x, y, 0)
        view.dispatchTouchEvent(d)
        view.postDelayed({
            view.dispatchTouchEvent(u)
            d.recycle()
            u.recycle()
        }, 60)
    }
}
