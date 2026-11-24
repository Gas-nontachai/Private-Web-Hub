package com.nonthachai.privatewebhub

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.InputDevice
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodChannel

/** A native overlay also works above WebView's fullscreen video view. */
class TvInput(private val activity: MainActivity, private val channel: MethodChannel) {
    var browserActive = false
        set(value) {
            if (value && !field) { x = .5f; y = .5f }
            field = value; cursor = value; update()
        }
    private var cursor = false
    private var x = 0.5f
    private var y = 0.5f
    private val pointer = object : View(activity) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        override fun onDraw(canvas: Canvas) {
            paint.color = Color.BLACK; canvas.drawCircle(width / 2f, height / 2f, 12f, paint)
            paint.color = Color.WHITE; canvas.drawCircle(width / 2f, height / 2f, 9f, paint)
            paint.color = Color.BLACK; canvas.drawCircle(width / 2f, height / 2f, 3f, paint)
        }
    }.apply { isFocusable = false; isClickable = false; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
    private val hidePointer = Runnable { pointer.visibility = View.GONE }

    fun key(event: KeyEvent): Boolean {
        if (!browserActive) return false
        if (event.keyCode == KeyEvent.KEYCODE_MENU) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) toggle()
            return true
        }
        if (!cursor) return false
        val action = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> "up"
            KeyEvent.KEYCODE_DPAD_DOWN -> "down"
            KeyEvent.KEYCODE_DPAD_LEFT -> "left"
            KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> "ok"
            KeyEvent.KEYCODE_PAGE_UP, KeyEvent.KEYCODE_CHANNEL_UP -> "scrollUp"
            KeyEvent.KEYCODE_PAGE_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> "scrollDown"
            else -> return false
        }
        if (event.action == KeyEvent.ACTION_DOWN && (action != "ok" || event.repeatCount == 0)) perform(action, if (event.repeatCount > 5) 0.04f else 0.02f)
        return true
    }

    fun toggle() { cursor = !cursor; update(); channel.invokeMethod("cursor", cursor) }
    fun state(): Map<String, Any> = mapOf("browser" to browserActive, "cursor" to cursor)
    fun move(dx: Float, dy: Float) {
        check(browserActive) { "Open a web page first" }
        cursor = true
        x = (x + dx).coerceIn(0.015f, 0.985f); y = (y + dy).coerceIn(0.02f, 0.98f)
        update()
    }
    fun perform(action: String, step: Float = 0.025f): Boolean {
        if (action == "cursor") { check(browserActive); toggle(); return true }
        if (browserActive && (action == "scrollUp" || action == "scrollDown")) {
            touch(true, if (action == "scrollDown") 1 else -1)
            return true
        }
        if (!browserActive || !cursor) return false
        when (action) {
            "up" -> move(0f, -step)
            "down" -> move(0f, step)
            "left" -> move(-step, 0f)
            "right" -> move(step, 0f)
            "ok" -> touch(false)
            "scrollUp" -> touch(true, -1)
            "scrollDown" -> touch(true, 1)
            else -> return false
        }
        return true
    }
    private fun touch(scroll: Boolean, direction: Int = 1) {
        update()
        val root = activity.window.decorView as ViewGroup
        val px = x * root.width; val py = y * root.height
        val now = SystemClock.uptimeMillis()
        fun send(action: Int, cy: Float, elapsed: Long) {
            val properties = MotionEvent.PointerProperties().apply { id = 0; toolType = MotionEvent.TOOL_TYPE_FINGER }
            val coordinates = MotionEvent.PointerCoords().apply { x = px; y = cy; pressure = 1f; size = 1f }
            val event = MotionEvent.obtain(now, now + elapsed, action, 1, arrayOf(properties), arrayOf(coordinates),
                0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
            root.dispatchTouchEvent(event); event.recycle()
        }
        if (scroll) {
            // A swipe reaches scrollable cross-origin frames without injecting page code.
            val start = root.height * if (direction > 0) .75f else .3f
            val end = root.height * if (direction > 0) .3f else .75f
            send(MotionEvent.ACTION_DOWN, start, 0)
            for (i in 1..8) root.postDelayed({ send(MotionEvent.ACTION_MOVE, start + (end - start) * i / 8, i * 25L) }, i * 25L)
            root.postDelayed({ send(MotionEvent.ACTION_UP, end, 225) }, 225)
        } else {
            send(MotionEvent.ACTION_DOWN, py, 0)
            root.postDelayed({ send(MotionEvent.ACTION_UP, py, 60) }, 60)
        }
    }
    private fun update() {
        val root = activity.window.decorView as ViewGroup
        if (pointer.parent == null) root.addView(pointer, FrameLayout.LayoutParams(32, 32))
        pointer.visibility = if (browserActive && cursor) View.VISIBLE else View.GONE
        pointer.removeCallbacks(hidePointer)
        if (browserActive && cursor) pointer.postDelayed(hidePointer, 3000)
        pointer.translationX = x * root.width - 16
        pointer.translationY = y * root.height - 16
        pointer.bringToFront()
    }
    fun refresh() { if (browserActive) update() }
    fun dispose() { pointer.removeCallbacks(hidePointer); (pointer.parent as? ViewGroup)?.removeView(pointer) }
}
