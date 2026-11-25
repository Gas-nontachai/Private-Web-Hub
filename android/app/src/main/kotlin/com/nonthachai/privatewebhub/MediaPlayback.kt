package com.nonthachai.privatewebhub

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.webkit.WebView
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONTokener
import java.lang.ref.WeakReference

/** One visible WebView owns playback. No page gets access to this platform channel. */
class MediaPlayback(private val activity: MainActivity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val runtime by lazy { activity.assets.open("flutter_assets/assets/runtime/media_runtime.js").bufferedReader().use { it.readText() } }
    private var web = WeakReference<WebView>(null)
    private var owner: String? = null
    private var hosts = emptySet<String>()
    private var allowSkip = false
    private var foreground = true
    private var audioOnly = false
    private var stopped = false
    private var state = JSONObject()
    private var attempts = 0
    private var generation = 0
    val playing get() = state.optBoolean("playing")
    private val supported get() = (activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) && Build.VERSION.SDK_INT >= 26 && !activity.isTelevision
    private val poll = object : Runnable {
        override fun run() {
            if (owner == null) return
            var target = web.get()
            if (target == null && attempts++ < 30) {
                target = activity.visibleWebView()
                web = WeakReference(target)
            }
            if (target != null) {
                val url = android.net.Uri.parse(target.url ?: "")
                if (url.scheme == "https" && url.host in hosts) {
                    val session = generation
                    target.evaluateJavascript(runtime) { result ->
                        if (session != generation || target.url != url.toString()) return@evaluateJavascript
                        try {
                            val value = JSONTokener(result).nextValue()
                            val snapshot = if (value is JSONObject) value else JSONObject(value as String)
                            update(snapshot)
                        } catch (_: Exception) { update(JSONObject()) }
                    }
                } else update(JSONObject())
            }
            main.postDelayed(this, 1000)
        }
    }
    fun attach(id: String, allowedHosts: List<String>, skip: Boolean) {
        if (!supported) return
        if (owner == id) return
        detach()
        owner = id
        hosts = allowedHosts.filter { it.length <= 253 && it.matches(Regex("[a-z0-9.-]+")) }.toSet()
        allowSkip = skip
        attempts = 0
        stopped = false
        main.post(poll)
    }
    fun detach(id: String? = owner) {
        if (id != owner) return
        command("stop")
        web.get()?.evaluateJavascript("window.__mvMedia?.pip(false)", null)
        generation++
        owner = null
        main.removeCallbacks(poll)
        web.clear()
        state = JSONObject()
        audioOnly = false
        activity.stopService(Intent(activity, PlaybackService::class.java))
        PlaybackService.controller = null
        pipParams()
    }
    private fun update(value: JSONObject) {
        state = value
        if (!playing) stopped = false
        if (playing && stopped) { command("pause"); return }
        if (playing && PlaybackService.controller?.get() !== this && (foreground || activity.isInPictureInPictureMode)) {
            try {
                PlaybackService.controller = WeakReference(this)
                activity.startForegroundService(Intent(activity, PlaybackService::class.java))
            } catch (error: RuntimeException) {
                PlaybackService.controller = null
                android.util.Log.w("MovieMedia", "Background playback unavailable", error)
            }
        }
        PlaybackService.instance?.update(state, allowSkip)
        pipParams()
    }
    fun command(action: String) {
        if (action !in setOf("play", "pause", "stop", "next", "previous")) return
        if (action in setOf("next", "previous") && (!allowSkip || !state.optBoolean(action))) return
        if (action == "stop") stopped = true
        web.get()?.evaluateJavascript("window.__mvMedia?.command(${JSONObject.quote(action)})", null)
        if (action == "stop") {
            state.put("playing", false)
            audioOnly = false
            activity.stopService(Intent(activity, PlaybackService::class.java))
            PlaybackService.controller = null
            pipParams()
        }
    }
    private fun pipParams() {
        if (!supported || !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val audio = Intent(activity, MainActivity::class.java).apply {
            action = ACTION_AUDIO
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val headphone = RemoteAction(Icon.createWithResource(activity, R.drawable.ic_headphones),
            "ฟังเบื้องหลัง", "ฟังเบื้องหลัง", PendingIntent.getActivity(activity, 921, audio, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        val toggle = PlaybackService.pending(activity, if (playing) "pause" else "play")
        val play = RemoteAction(Icon.createWithResource(activity, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play),
            if (playing) "พัก" else "เล่น", "เล่น / พัก", toggle)
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).setActions(listOf(play, headphone))
        if (Build.VERSION.SDK_INT >= 31) builder.setAutoEnterEnabled(owner != null && playing && state.optBoolean("video") && !audioOnly)
        try { activity.setPictureInPictureParams(builder.build()) } catch (_: IllegalStateException) { }
    }
    fun leave() {
        if (!supported || !playing || audioOnly) return
        if (!state.optBoolean("video") || !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            audioOnly = true
            return
        }
        if (Build.VERSION.SDK_INT < 31 && activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            try { activity.enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()) }
            catch (_: IllegalStateException) { }
        }
    }
    fun pipChanged(active: Boolean) {
        web.get()?.evaluateJavascript("window.__mvMedia?.pip($active)", null)
        channel.invokeMethod("pip", active)
    }
    fun audioMode() {
        audioOnly = true
        pipParams()
        // The activity PendingIntent expands PiP; hide the same activity without destroying its WebView.
        main.postDelayed({ activity.moveTaskToBack(true) }, 250)
    }
    fun started() { foreground = true; audioOnly = false; pipParams() }
    fun stopped() {
        foreground = false
        if (!supported) return
        if (!(activity.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager).isInteractive && playing) audioOnly = true
        if (!activity.isInPictureInPictureMode && !audioOnly) command("stop")
    }
    companion object { const val ACTION_AUDIO = "com.nonthachai.privatewebhub.MEDIA_AUDIO" }
}
