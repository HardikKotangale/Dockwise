package com.ytchannel.standbypro

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.view.View
import android.view.WindowManager

/**
 * Watches for "charging + propped up" and opens Dockwise by itself.
 *
 * Battery: the tilt sensor is only listened to while a charger is connected
 * (and at a low rate); on battery the service just waits for the plug event.
 */
class StandbyService : Service(), SensorEventListener {
    companion object {
        const val ACTION_EXIT = "com.ytchannel.standbypro.EXIT"
        const val ACTION_DEBUG_FORCE = "com.ytchannel.standbypro.DEBUG_FORCE_POSTURE"
        const val PREFS = "standby_auto"
        private const val WATCH_CHANNEL = "standby_watch"
        private const val OPEN_CHANNEL = "standby_open"
        private const val WATCH_ID = 41
        private const val OPEN_ID = 42

        @Volatile var running = false

        fun loadConfig(ctx: Context): PostureLogic.Config {
            val p = ctx.getSharedPreferences(PREFS, MODE_PRIVATE)
            return PostureLogic.Config(
                minLeanDeg = p.getFloat("leanDeg", 40f).toDouble(),
                landscapeOnly = p.getBoolean("landscapeOnly", true),
            )
        }
    }

    private val logic = PostureLogic()
    private var sensorManager: SensorManager? = null
    private var charging = false
    private val session = AutoSession.shared // see spec/AutoLaunch.tla
    private var launchTask: Runnable? = null // the 700 ms delayed startActivity
    private var watchdog: Runnable? = null // notices a launch Android silently refused
    private var exitOnUnplug = true
    private var usingGravity = true
    private val filtered = FloatArray(3)
    private val main = Handler(Looper.getMainLooper())
    private var wake: PowerManager.WakeLock? = null

    private val power = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_POWER_CONNECTED -> setCharging(true)
                Intent.ACTION_POWER_DISCONNECTED -> setCharging(false)
                ACTION_DEBUG_FORCE -> openApp() // debug builds only (see onCreate)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        running = true
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        createChannels()
        val note = Notification.Builder(this, WATCH_CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Dockwise is ready")
            .setContentText("Opens when you charge the phone and prop it up")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(WATCH_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(WATCH_ID, note)
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                addAction(ACTION_DEBUG_FORCE)
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(power, filter, RECEIVER_EXPORTED) // debug action comes from adb
        } else {
            registerReceiver(power, filter)
        }
        session.serviceStarted() // forget what an earlier service instance knew
        // already plugged in when the service starts?
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        setCharging((battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0)
    }

    // Called on every start: re-read the settings the app just saved.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        logic.config = loadConfig(this)
        exitOnUnplug = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("exitOnUnplug", true)
        return START_STICKY
    }

    private fun setCharging(on: Boolean) {
        if (on == charging) return
        charging = on
        val closeApp = session.setCharging(on) // also cancels a queued launch
        if (on) {
            startSensors()
        } else {
            stopSensors()
            logic.reset()
            cancelPendingLaunch()
            if (exitOnUnplug && closeApp) sendBroadcast(Intent(ACTION_EXIT).setPackage(packageName))
        }
    }

    private fun startSensors() {
        val sm = sensorManager ?: return
        val gravity = sm.getDefaultSensor(Sensor.TYPE_GRAVITY)
        usingGravity = gravity != null
        val sensor = gravity ?: sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL) // ~5 Hz
        // Sensors stop delivering once the screen is off and the CPU sleeps, so hold
        // the CPU awake while charging (screen stays off; the phone is on power anyway).
        if (wake == null) {
            wake = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dockwise:posture")
                .apply { setReferenceCounted(false); acquire() }
        }
    }

    private fun stopSensors() {
        sensorManager?.unregisterListener(this)
        wake?.let { if (it.isHeld) it.release() }
        wake = null
    }

    override fun onSensorChanged(e: SensorEvent) {
        var x = e.values[0]
        var y = e.values[1]
        var z = e.values[2]
        if (!usingGravity) { // accelerometer includes shaking: smooth it out
            filtered[0] = 0.8f * filtered[0] + 0.2f * x
            filtered[1] = 0.8f * filtered[1] + 0.2f * y
            filtered[2] = 0.8f * filtered[2] + 0.2f * z
            x = filtered[0]; y = filtered[1]; z = filtered[2]
        }
        val active = logic.onSample(x.toDouble(), y.toDouble(), z.toDouble(), SystemClock.elapsedRealtime())
        if (session.onPosture(active)) openApp() // edge: became active, while charging
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun cancelPendingLaunch() {
        launchTask?.let(main::removeCallbacks)
        launchTask = null
        watchdog?.let(main::removeCallbacks)
        watchdog = null
    }

    private fun appIntent() = Intent(this, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        putExtra("auto", true) // so "close when unplugged" only closes this launch
    }

    // Android 10+ stops background apps opening screens. With "Display over
    // other apps" granted, showing a 1-pixel overlay first makes the app count
    // as visible, which lets the launch through. Otherwise: a notification.
    private fun openApp() {
        // Locked or asleep: a background launch is refused, but a full-screen-intent
        // notification may open over the lock screen and turns the screen on.
        val locked = (getSystemService(KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked
        if (!locked && Settings.canDrawOverlays(this)) {
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            val dot = View(this)
            try {
                wm.addView(dot, WindowManager.LayoutParams(
                    1, 1, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT))
                // the overlay must be on screen before Android counts us as visible
                session.launchQueued()
                val task = Runnable {
                    launchTask = null
                    if (!session.launchDue()) return@Runnable // unplugged meanwhile: do nothing
                    try { startActivity(appIntent()) } catch (_: Exception) { notifyToOpen() }
                    // Android can refuse a background launch WITHOUT any error. If the
                    // screen has not appeared 3 s later, offer the notification instead
                    // (TLC: spec/results/AutoLaunch_live_original.txt).
                    val w = Runnable {
                        watchdog = null
                        if (session.watchdogDue()) notifyToOpen()
                    }
                    watchdog = w
                    main.postDelayed(w, 3000)
                }
                launchTask = task
                main.postDelayed(task, 700)
                main.postDelayed({ runCatching { wm.removeView(dot) } }, 2500)
                return
            } catch (_: Exception) {
                runCatching { wm.removeView(dot) }
            }
        }
        notifyToOpen()
    }

    private fun notifyToOpen() {
        val open = PendingIntent.getActivity(
            this, 0, appIntent(), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(this, OPEN_CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Charging and propped up")
            .setContentText("Tap to open Dockwise")
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(open)
            .setFullScreenIntent(open, true) // opens by itself if Android allows it
            .setAutoCancel(true)
            .build()
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(OPEN_ID, n)
    }

    private fun createChannels() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(WATCH_CHANNEL, "Auto-start", NotificationManager.IMPORTANCE_MIN)
                .apply { description = "Keeps Dockwise ready to open when you dock the phone" })
        nm.createNotificationChannel(
            NotificationChannel(OPEN_CHANNEL, "Open Dockwise", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "Shown when Dockwise cannot open on its own" })
    }

    override fun onDestroy() {
        running = false
        cancelPendingLaunch()
        session.serviceStarted()
        stopSensors()
        runCatching { unregisterReceiver(power) }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
