package com.ytchannel.standbypro

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

/**
 * Spotify's redirect (dockwise://spotify-callback) lands here. Same as the plugin's
 * own CallbackActivity (which is final), plus: pull Dockwise back in front of the browser.
 */
class SpotifyCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent?.data
        url?.scheme?.let { FlutterWebAuth2Plugin.callbacks.remove(it)?.success(url.toString()) }
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            ),
        )
        finishAndRemoveTask()
    }
}
