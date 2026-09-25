package sy.earlywarning.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

// Creates the notification channel that carries the custom siren sound
// (res/raw/alarm.mp3) before any notification is ever shown. This runs in
// Application.onCreate() rather than MainActivity so the channel exists
// even if the process was started in the background to handle a push
// message, not just when the user opens the app's UI.
class EarlyWarningApplication : Application() {
    companion object {
        const val SIREN_CHANNEL_ID = "disaster_siren_channel"
    }

    override fun onCreate() {
        super.onCreate()
        createSirenNotificationChannel()
    }

    private fun createSirenNotificationChannel() {
        // Notification channels don't exist before Android 8 (API 26) — on
        // older versions Android just uses the notification's default sound.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        // Numeric resource id instead of the resource name: some OEM skins
        // (e.g. ColorOS) ignore the name-based form and play no sound.
        val soundUri = Uri.parse("android.resource://$packageName/${R.raw.alarm}")
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            SIREN_CHANNEL_ID,
            "Disaster Siren Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Critical disaster alerts that must play the siren sound"
            setSound(soundUri, audioAttributes)
            enableVibration(true)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }
}
