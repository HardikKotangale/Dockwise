package com.ytchannel.standbypro

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import androidx.core.content.ContextCompat
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings
import java.io.ByteArrayOutputStream
import android.media.AudioManager
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "standby_pro/system"

    // Auto-start: opened by the charger watcher (not by the user)?
    private var launchedByAuto = false
    private val exitReceiver = object : BroadcastReceiver() {
        // phone unplugged: close, but only a screen the watcher opened
        override fun onReceive(c: Context, i: Intent) {
            if (launchedByAuto) finishAndRemoveTask()
        }
    }

    // live tilt reading for the settings screen (only while it is open)
    private var probe: SensorEventListener? = null
    private var probeReading: PostureLogic.Reading? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        launchedByAuto = intent?.getBooleanExtra("auto", false) == true
        val filter = IntentFilter(StandbyService.ACTION_EXIT)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(exitReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(exitReceiver, filter)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("auto", false)) launchedByAuto = true
    }

    // Battery level straight from Android's own battery broadcast, which the
    // system refreshes on every 1% change. (The "battery property" other
    // packages read is cached or slow on some phones, so the percentage lagged.)
    private fun batteryInfo(): Map<String, Any>? {
        val i = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return null
        val level = i.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, 100)
        if (level < 0 || scale <= 0) return null
        return mapOf(
            "level" to level * 100 / scale,
            "charging" to (i.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) != 0),
            "full" to (i.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ==
                android.os.BatteryManager.BATTERY_STATUS_FULL),
        )
    }

    // Room light in lux. The sensor is only listened to while the app is on screen
    // and is started by the first request.
    private var lightListener: SensorEventListener? = null
    private var lastLux: Float? = null

    private fun ambientLux(): Double? {
        if (lightListener == null) {
            val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            val sensor = sm.getDefaultSensor(Sensor.TYPE_LIGHT) ?: return null
            val l = object : SensorEventListener {
                override fun onSensorChanged(e: SensorEvent) { lastLux = e.values[0] }
                override fun onAccuracyChanged(s: Sensor?, a: Int) {}
            }
            sm.registerListener(l, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            lightListener = l
        }
        return lastLux?.toDouble()
    }

    private fun stopLight() {
        lightListener?.let { (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(it) }
        lightListener = null
        lastLux = null
    }

    override fun onPause() {
        stopLight() // off screen: stop listening; the next request starts it again
        super.onPause()
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(exitReceiver) }
        stopLight()
        stopProbe()
        super.onDestroy()
    }

    private fun startProbe() {
        if (probe != null) return
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sm.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        probe = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                probeReading = PostureLogic.reading(
                    e.values[0].toDouble(), e.values[1].toDouble(), e.values[2].toDouble())
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        sm.registerListener(probe, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private fun stopProbe() {
        probe?.let { (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(it) }
        probe = null
        probeReading = null
    }

    private fun openSettings(action: String, withPackage: Boolean = false): Boolean = try {
        val i = Intent(action)
        if (withPackage) i.data = Uri.parse("package:$packageName")
        startActivity(i)
        true
    } catch (e: Exception) {
        false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepAwake" -> {
                    val enabled = getArgument<Boolean>(call.arguments, "enabled")
                    if (enabled == null) {
                        result.error("INVALID_ARGUMENT", "setKeepAwake requires an enabled boolean.", null)
                    } else {
                        setKeepAwake(enabled)
                        result.success(true)
                    }
                }
                "setBrightness" -> {
                    val value = getArgument<Number>(call.arguments, "value")
                    if (value == null) {
                        result.error("INVALID_ARGUMENT", "setBrightness requires a numeric value.", null)
                    } else {
                        setBrightness(value.toDouble())
                        result.success(true)
                    }
                }
                "mediaCommand" -> {
                    val command = getArgument<String>(call.arguments, "command")
                    val handled = command?.let(::dispatchMediaCommand) ?: false
                    if (handled) {
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Unsupported media command: $command", null)
                    }
                }
                "hasNotificationAccess" -> result.success(hasNotificationAccess())
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "setPreferredPlayer" -> {
                    preferredPackage = getArgument<String>(call.arguments, "package") ?: ""
                    result.success(true)
                }
                "mediaPlayers" -> result.success(mediaPlayers())
                "configureAutoStart" -> {
                    val enabled = getArgument<Boolean>(call.arguments, "enabled") ?: false
                    getSharedPreferences(StandbyService.PREFS, Context.MODE_PRIVATE).edit()
                        .putBoolean("enabled", enabled)
                        .putFloat("leanDeg", (getArgument<Number>(call.arguments, "leanDeg") ?: 40).toFloat())
                        .putBoolean("landscapeOnly", getArgument<Boolean>(call.arguments, "landscapeOnly") ?: true)
                        .putBoolean("exitOnUnplug", getArgument<Boolean>(call.arguments, "exitOnUnplug") ?: true)
                        .apply()
                    val svc = Intent(this, StandbyService::class.java)
                    if (enabled) ContextCompat.startForegroundService(this, svc) else stopService(svc)
                    result.success(true)
                }
                "autoStartStatus" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(mapOf(
                        "overlay" to Settings.canDrawOverlays(this),
                        "notifications" to nm.areNotificationsEnabled(),
                        "battery" to pm.isIgnoringBatteryOptimizations(packageName),
                        "running" to StandbyService.running,
                    ))
                }
                "openOverlaySettings" ->
                    result.success(openSettings(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, withPackage = true))
                "openBatterySettings" ->
                    result.success(openSettings(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                        result.success(true)
                    } else {
                        // already asked (or older Android): open the app's notification settings
                        val ok = try {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                            true
                        } catch (e: Exception) {
                            false
                        }
                        result.success(ok)
                    }
                }
                "postureProbe" -> {
                    if (getArgument<Boolean>(call.arguments, "on") == true) startProbe() else stopProbe()
                    result.success(true)
                }
                "postureNow" -> {
                    val r = probeReading
                    if (r == null) {
                        result.success(null)
                    } else {
                        val logic = PostureLogic(PostureLogic.Config(
                            minLeanDeg = (getArgument<Number>(call.arguments, "leanDeg") ?: 40).toDouble(),
                            landscapeOnly = getArgument<Boolean>(call.arguments, "landscapeOnly") ?: true))
                        result.success(mapOf("lean" to r.leanDeg, "roll" to r.rollDeg, "matches" to logic.matches(r)))
                    }
                }
                "deviceModel" -> result.success(android.os.Build.MODEL)
                "ambientLux" -> result.success(ambientLux()) // null: no light sensor/reading yet
                "batteryInfo" -> result.success(batteryInfo())
                "launchApp" -> {
                    val pkg = getArgument<String>(call.arguments, "package")
                    val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                    if (intent == null) {
                        result.success(false)
                    } else {
                        startActivity(intent)
                        result.success(true)
                    }
                }
                "nowPlaying" -> result.success(nowPlaying())
                "seekTo" -> {
                    val pos = getArgument<Number>(call.arguments, "positionMs")?.toLong() ?: 0L
                    val controller = activeController()
                    controller?.transportControls?.seekTo(pos.coerceAtLeast(0))
                    result.success(controller != null)
                }
                "seekBy" -> {
                    val delta = getArgument<Number>(call.arguments, "deltaMs")?.toLong() ?: 0L
                    result.success(seekBy(delta))
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> getArgument(arguments: Any?, key: String): T? {
        return when (arguments) {
            is Map<*, *> -> arguments[key] as? T
            else -> arguments as? T
        }
    }

    private fun setKeepAwake(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun setBrightness(value: Double) {
        val attributes = window.attributes
        attributes.screenBrightness = value.coerceIn(0.0, 1.0).toFloat()
        window.attributes = attributes
    }

    private fun dispatchMediaCommand(command: String): Boolean {
        // Prefer the exact session shown on the card; media keys go to whichever
        // app Android last treated as current, which may be a different player.
        activeController()?.let { c ->
            val controls = c.transportControls
            when (command) {
                "playPause" ->
                    if (c.playbackState?.state == PlaybackState.STATE_PLAYING) controls.pause() else controls.play()
                "next" -> controls.skipToNext()
                "previous" -> controls.skipToPrevious()
                else -> return false
            }
            return true
        }
        val keyCode = when (command) {
            "playPause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return false
        }

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        return true
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return enabled?.contains(packageName) == true
    }

    // Needs notification access; null if not granted or nothing is playing.
    private var preferredPackage = "" // "" = automatic
    private var lastPackage = "" // sticky: keep following the same player

    private fun sessions(): List<android.media.session.MediaController> {
        if (!hasNotificationAccess()) return emptyList()
        val manager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        return try {
            manager.getActiveSessions(ComponentName(this, MediaListenerService::class.java))
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    private fun activeController(): android.media.session.MediaController? {
        val all = sessions()
        if (preferredPackage.isNotEmpty()) return all.firstOrNull { it.packageName == preferredPackage }
        fun playing(c: android.media.session.MediaController) = c.playbackState?.state == PlaybackState.STATE_PLAYING
        val pick = all.firstOrNull { it.packageName == lastPackage && playing(it) }
            ?: all.firstOrNull { playing(it) }
            ?: all.firstOrNull { it.packageName == lastPackage }
            ?: all.firstOrNull()
        pick?.let { lastPackage = it.packageName }
        return pick
    }

    private fun mediaPlayers(): List<Map<String, String>> =
        sessions().map { mapOf("package" to it.packageName, "app" to appLabel(it.packageName)) }

    private fun seekBy(deltaMs: Long): Boolean {
        val controller = activeController() ?: return false
        val position = livePosition(controller.playbackState)
        controller.transportControls.seekTo((position + deltaMs).coerceAtLeast(0))
        return true
    }

    private fun nowPlaying(): Map<String, Any?>? {
        val controller = activeController() ?: return null
        val meta = controller.metadata ?: return null
        val state = controller.playbackState
        return mapOf(
            "title" to meta.getString(MediaMetadata.METADATA_KEY_TITLE),
            "artist" to (meta.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)),
            "app" to appLabel(controller.packageName),
            "duration" to meta.getLong(MediaMetadata.METADATA_KEY_DURATION),
            "position" to livePosition(state),
            "playing" to (state?.state == PlaybackState.STATE_PLAYING),
            "art" to (meta.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: meta.getBitmap(MediaMetadata.METADATA_KEY_ART))?.let(::toPng),
        )
    }

    // "com.google.android.youtube" -> "YouTube". Package visibility can hide
    // other apps' labels on Android 11+, so known players are named directly.
    private fun appLabel(pkg: String): String {
        val known = mapOf(
            "com.spotify.music" to "Spotify",
            "com.google.android.youtube" to "YouTube",
            "com.google.android.apps.youtube.music" to "YouTube Music",
            "com.apple.android.music" to "Apple Music",
            "com.amazon.mp3" to "Amazon Music",
            "com.jio.media.jiobeats" to "JioSaavn",
            "com.gaana" to "Gaana",
        )
        known[pkg]?.let { return it }
        return try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (e: Exception) {
            pkg.substringAfterLast('.').replaceFirstChar { it.uppercase() }
        }
    }

    // PlaybackState.position is the value at lastPositionUpdateTime; advance it.
    private fun livePosition(state: PlaybackState?): Long {
        if (state == null) return 0L
        if (state.state != PlaybackState.STATE_PLAYING) return state.position
        val elapsed = android.os.SystemClock.elapsedRealtime() - state.lastPositionUpdateTime
        return state.position + (elapsed * state.playbackSpeed).toLong()
    }

    private fun toPng(bitmap: Bitmap): ByteArray {
        val scaled = Bitmap.createScaledBitmap(bitmap, 256, 256, true)
        return ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.PNG, 90, it) }.toByteArray()
    }
}
