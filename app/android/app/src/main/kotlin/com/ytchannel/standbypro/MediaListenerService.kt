package com.ytchannel.standbypro

import android.service.notification.NotificationListenerService

// Intentionally empty: enabling this in "Notification access" is what lets
// MediaSessionManager.getActiveSessions() return other apps' sessions.
class MediaListenerService : NotificationListenerService()
