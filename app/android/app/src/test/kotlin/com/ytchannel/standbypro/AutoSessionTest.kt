package com.ytchannel.standbypro

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Replays of the counterexamples TLC found in spec/AutoLaunch.tla (the traces are in
 * spec/results/AutoLaunch_*.txt and spec/README.md), plus the happy paths. The
 * comments say which trace each test pins down.
 */
class AutoSessionTest {
    // the watcher sees the phone docked: plugged in, posture became active, launch queued
    private fun docked(s: AutoSession) {
        s.setCharging(true)
        assertTrue(s.onPosture(true)) // openApp() runs
        s.launchQueued()
    }

    // what MainActivity does when the launch really happens
    private fun autoLaunch(s: AutoSession) {
        assertTrue(s.launchDue()) // startActivity() is called
        s.activityCreated(true)
        s.activityShown()
    }

    // ---------- happy paths ----------

    @Test fun anAutoOpenedScreenClosesWhenTheChargerIsUnplugged() {
        val s = AutoSession()
        docked(s)
        autoLaunch(s)
        assertTrue(s.setCharging(false))
    }

    @Test fun aScreenTheUserOpenedAloneIsNeverClosedByAnUnplug() {
        val s = AutoSession()
        s.activityCreated(false)
        s.activityShown()
        s.setCharging(true)
        assertFalse(s.setCharging(false))
    }

    @Test fun theLaunchHappensOncePerDockingNotOnEverySample() {
        val s = AutoSession()
        assertFalse(s.onPosture(true)) // not charging: the sensors are not even running
        s.setCharging(true)
        assertTrue(s.onPosture(true))
        assertFalse(s.onPosture(true)) // still active: no second launch
        assertFalse(s.onPosture(false))
        assertTrue(s.onPosture(true)) // lifted and set down again: a new docking
    }

    @Test fun unplugAndReplugCanLaunchAgain() {
        val s = AutoSession()
        docked(s)
        autoLaunch(s)
        s.setCharging(false)
        s.activityDestroyed()
        s.setCharging(true)
        assertTrue(s.onPosture(true)) // the dock edge fires again after a re-plug
    }

    // ---------- AutoLaunch_race: unplug while the 700 ms launch is queued ----------
    // TLC trace: Plug, PostureChange(overlay), Unplug, PerformLaunch  ->  the screen
    // opened after the charger was out and nothing ever closed it.

    @Test fun unpluggingCancelsALaunchThatIsStillQueued() {
        val s = AutoSession()
        docked(s) // startActivity is queued for 700 ms from now
        assertFalse(s.setCharging(false)) // unplugged inside those 700 ms; no app to close yet
        assertFalse(s.pendingLaunch) // the queued launch was cancelled (FixRace)...
        assertFalse(s.launchDue()) // ...and even if it fires, it does nothing
        assertFalse(s.watchdogDue())
    }

    // ---------- AutoLaunch_ownership: the user opens the app while the launch is queued ----------
    // TLC trace: Plug, PostureChange, UserOpen, PerformLaunch, Unplug  ->  the unplug closed
    // the screen the user had just opened (the late onNewIntent claimed it for the watcher).

    @Test fun anAutoLaunchDoesNotClaimAScreenTheUserAlreadyHasOpen() {
        val s = AutoSession()
        docked(s)
        s.activityCreated(false) // the user taps the icon during the 700 ms...
        s.activityShown()
        assertTrue(s.launchDue()) // ...then the queued launch arrives as onNewIntent
        s.activityNewIntent(true)
        assertFalse(s.setCharging(false)) // the user's screen stays open
    }

    // ---------- AutoLaunch_ownership_partial: leave and come back ----------
    // TLC trace: Plug, PostureChange, PerformLaunch, UserHome, UserOpen, Unplug  ->  the
    // user went Home and came back (no new intent), but the old claim survived.

    @Test fun goingHomeEndsTheWatchersClaimOnTheScreen() {
        val s = AutoSession()
        docked(s)
        autoLaunch(s)
        s.userLeft() // Home pressed
        s.activityHidden()
        s.activityShown() // the user comes back: onResume, no new intent
        assertFalse(s.setCharging(false))
    }

    @Test fun anAutoLaunchThatBringsABackgroundedAppForwardStillOwnsIt() {
        val s = AutoSession()
        s.activityCreated(false) // the user opened it earlier...
        s.activityShown()
        s.userLeft() // ...and went Home
        s.activityHidden()
        s.setCharging(true)
        assertTrue(s.onPosture(true))
        s.launchQueued()
        assertTrue(s.launchDue())
        s.activityNewIntent(true) // the watcher brings it to the front (nobody was looking)
        s.activityShown()
        assertTrue(s.setCharging(false)) // so it closes on unplug as promised
    }

    // ---------- AutoLaunch_live_original: Android silently refuses the launch ----------
    // TLC lasso: Plug, PostureChange, PerformLaunch(silent), then nothing forever  ->  no
    // screen and no notification, and no retry (the dock edge only fires once).

    @Test fun aLaunchThatNeverShowedTheScreenIsNoticedByTheWatchdog() {
        val s = AutoSession()
        docked(s)
        assertTrue(s.launchDue()) // startActivity() returned without any error...
        assertTrue(s.watchdogDue()) // ...3 s later nothing is on screen: post the notification
    }

    @Test fun noNotificationIsNeededWhenTheScreenDidAppear() {
        val s = AutoSession()
        docked(s)
        autoLaunch(s)
        assertFalse(s.watchdogDue())
    }

    @Test fun noNotificationIsPostedForAChargerThatIsGone() {
        val s = AutoSession()
        docked(s)
        assertTrue(s.launchDue())
        s.setCharging(false)
        assertFalse(s.watchdogDue())
    }

    // ---------- bookkeeping ----------

    @Test fun aNewServiceForgetsTheOldChargerState() {
        val s = AutoSession()
        docked(s)
        s.serviceStarted() // the service was recreated while the activity lives on
        assertFalse(s.launchDue())
        s.setCharging(true) // it counts as a fresh plug-in, not a duplicate event
        assertTrue(s.onPosture(true))
    }

    @Test fun closingTheScreenForgetsTheClaim() {
        val s = AutoSession()
        docked(s)
        autoLaunch(s)
        s.activityDestroyed() // the user swiped it away
        assertFalse(s.setCharging(false)) // nothing left to close
    }
}
