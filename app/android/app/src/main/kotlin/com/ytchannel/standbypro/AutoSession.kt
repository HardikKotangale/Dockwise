package com.ytchannel.standbypro

/**
 * The decisions behind auto-launch, in plain Kotlin (no Android classes) so they
 * are unit-tested on the JVM. The charger watcher (StandbyService) and the screen
 * (MainActivity) both talk to ONE shared instance, which is what makes the rules
 * below possible to state at all.
 *
 * This class mirrors spec/AutoLaunch.tla variable for variable and action for
 * action (see the table in spec/README.md). TLC checked the PlusCal model, found
 * three flaws in the previous code, and these rules are the fixes:
 *
 *  R1  Unplugging must not close a screen the user opened or took over.
 *        - [activityNewIntent]: an auto-launch must not claim a screen that is
 *          already on show (FixNewIntent).
 *        - [userLeft]: pressing Home ends the "opened by auto" claim (FixLeave).
 *  R2  Nothing the watcher opened may be left open after the charger is out.
 *        - [setCharging] cancels a launch still waiting in postDelayed (FixRace).
 *  R3  Docked and charging, the user is eventually shown the app or offered the
 *      notification.
 *        - [watchdogDue]: Android can refuse a background launch without any
 *          error; if the screen has not appeared, the notification is posted.
 *
 * All callbacks run on the main thread, so no locking is needed.
 */
class AutoSession {
    companion object {
        /** The one instance the service and the activity share. */
        val shared = AutoSession()
    }

    // ---- state of the service side (spec: charging, wasActive, pendingLaunch) ----
    var charging = false
        private set
    private var wasActive = false
    var pendingLaunch = false
        private set

    // ---- state of the activity side (spec: appTask, visible, launchedByAuto) ----
    private var alive = false // the activity exists
    var visible = false // on screen (between onResume and onPause)
        private set

    /** Opened by the watcher and not since taken over by the user. */
    var launchedByAuto = false
        private set

    /** The service was (re)created: forget what the previous one knew about the charger. */
    fun serviceStarted() {
        charging = false
        wasActive = false
        pendingLaunch = false
    }

    /**
     * The charger was plugged in or out. Returns true when an auto-opened screen
     * must be closed now (unplugged while the watcher's screen is open).
     */
    fun setCharging(on: Boolean): Boolean {
        if (on == charging) return false
        charging = on
        if (on) return false
        wasActive = false // logic.reset(); wasActive = false
        pendingLaunch = false // FixRace: a launch still in postDelayed is cancelled
        return alive && launchedByAuto // the exit receiver's rule
    }

    /**
     * The debounced posture changed. Returns true when openApp() should run:
     * only on the edge "became active", and only while charging.
     */
    fun onPosture(active: Boolean): Boolean {
        if (!charging) return false // the sensors only run while charging
        val open = active && !wasActive
        wasActive = active
        return open
    }

    /** openApp() chose the overlay route: startActivity is queued for 700 ms from now. */
    fun launchQueued() {
        pendingLaunch = true
    }

    /** The 700 ms are over. True if startActivity should really be called. */
    fun launchDue(): Boolean {
        val go = pendingLaunch && charging // never launch for a charger that is gone
        pendingLaunch = false
        return go
    }

    /**
     * Some seconds after startActivity: did the screen come up? Android can refuse
     * a launch from the background without throwing, so the answer is not implied.
     * True means "post the tap-to-open notification instead".
     */
    fun watchdogDue(): Boolean = charging && !visible

    // ---- activity lifecycle ----

    fun activityCreated(byAuto: Boolean) {
        alive = true
        launchedByAuto = byAuto
    }

    /** An intent arrived for an activity that already exists. */
    fun activityNewIntent(byAuto: Boolean) {
        // FixNewIntent: if the user is looking at the screen, an auto-launch does
        // not make it the watcher's screen (it would then close on unplug).
        if (byAuto && !visible) launchedByAuto = true
    }

    fun activityShown() {
        visible = true
    }

    fun activityHidden() {
        visible = false
    }

    /** Home or Recents pressed (onUserLeaveHint): the user is using the phone now. */
    fun userLeft() {
        launchedByAuto = false // FixLeave
    }

    fun activityDestroyed() {
        alive = false
        visible = false
        launchedByAuto = false
    }
}
