package com.nonthachai.privatewebhub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import org.json.JSONObject
import java.lang.ref.WeakReference

/** Retains the process, not a second player. Android WebView owns audio focus. */
class PlaybackService : Service() {
    private lateinit var session: MediaSession
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { PlaybackService.controller?.get()?.command("pause") }
    }
    override fun onCreate() {
        super.onCreate()
        instance = this
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "การเล่นเบื้องหลัง", NotificationManager.IMPORTANCE_LOW))
        session = MediaSession(this, "Movie.exe").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { PlaybackService.controller?.get()?.command("play") }
                override fun onPause() { PlaybackService.controller?.get()?.command("pause") }
                override fun onStop() { PlaybackService.controller?.get()?.command("stop") }
                override fun onSkipToNext() { PlaybackService.controller?.get()?.command("next") }
                override fun onSkipToPrevious() { PlaybackService.controller?.get()?.command("previous") }
            })
            isActive = true
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), RECEIVER_NOT_EXPORTED)
        else registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        update(JSONObject(), false)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val target = PlaybackService.controller?.get()
        if (target == null) { stopSelf(); return START_NOT_STICKY }
        intent?.getStringExtra("command")?.let { target.command(it) }
        return START_NOT_STICKY
    }
    fun update(value: JSONObject, allowSkip: Boolean) {
        val playing = value.optBoolean("playing")
        val next = allowSkip && value.optBoolean("next")
        val previous = allowSkip && value.optBoolean("previous")
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP
        if (next) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (previous) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        session.setPlaybackState(PlaybackState.Builder().setActions(actions)
            .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                (value.optDouble("position", 0.0).coerceAtLeast(0.0) * 1000).toLong(), if (playing) 1f else 0f).build())
        session.setMetadata(MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, value.optString("title", "Movie.exe").take(200))
            .putString(MediaMetadata.METADATA_KEY_ARTIST, value.optString("artist").take(200))
            .putLong(MediaMetadata.METADATA_KEY_DURATION, (value.optDouble("duration", 0.0).coerceAtLeast(0.0) * 1000).toLong()).build())
        val open = PendingIntent.getActivity(this, 920, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun action(icon: Int, title: String, command: String, enabled: Boolean = true) = Notification.Action.Builder(
            icon, title, if (enabled) pending(this, command) else null).build()
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(value.optString("title", "Movie.exe").take(200))
            .setContentText(value.optString("artist").take(200))
            .setContentIntent(open).setOnlyAlertOnce(true).setOngoing(playing)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(action(android.R.drawable.ic_media_previous, "ก่อนหน้า", "previous", previous))
            .addAction(action(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "พัก" else "เล่น", if (playing) "pause" else "play"))
            .addAction(action(android.R.drawable.ic_media_next, "ถัดไป", "next", next))
            .addAction(action(android.R.drawable.ic_menu_close_clear_cancel, "หยุด", "stop"))
            .setDeleteIntent(pending(this, "stop"))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2)).build()
        startForeground(922, notification)
    }
    override fun onTaskRemoved(rootIntent: Intent?) { PlaybackService.controller?.get()?.command("stop"); stopSelf() }
    override fun onDestroy() {
        unregisterReceiver(noisy)
        session.release()
        instance = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    companion object {
        private const val CHANNEL = "movie_playback"
        var controller: WeakReference<MediaPlayback>? = null
        var instance: PlaybackService? = null
        fun pending(context: Context, command: String): PendingIntent = PendingIntent.getService(context,
            command.hashCode(), Intent(context, PlaybackService::class.java).putExtra("command", command),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
