package com.ytchannel.standbypro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/** After a reboot, bring the charger watcher back if Auto-start is on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val enabled = context.getSharedPreferences(StandbyService.PREFS, Context.MODE_PRIVATE)
            .getBoolean("enabled", false)
        if (enabled) {
            ContextCompat.startForegroundService(context, Intent(context, StandbyService::class.java))
        }
    }
}
