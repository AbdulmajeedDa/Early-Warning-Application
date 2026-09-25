// Firebase Cloud Messaging wiring: permission, device token registration,
// and playing the siren when an alert with trigger_siren arrives while the
// app is open. This file only handles the mechanics — main.dart owns what
// the foreground alert popup actually looks like, since that needs the
// app's theme/translation helpers.

import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_client.dart';

// Runs in a separate isolate when a message arrives while the app is in the
// background or terminated. Android already shows the notification (using
// the siren notification channel set up natively) and plays its sound by
// itself in that case — this handler only needs to exist because
// FirebaseMessaging requires one to be registered, there's nothing else to
// do here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotifications {
  static final AudioPlayer _player = AudioPlayer();

  static Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  /// Syncs this device's push settings with the backend: call it after a
  /// login/verification, on every app start while logged in, and whenever
  /// the user flips a switch on the Permissions screen.
  ///
  /// - Notifications switched off: removes this device's token from the
  ///   server so no push (and no siren) is sent to it at all. The alert is
  ///   still saved in the user's in-app list.
  /// - Notifications on: registers the token together with whether the alert
  ///   sound switch is on. With sound off, the server still sends the push
  ///   but with the phone's normal notification tone instead of the siren.
  static Future<void> registerDeviceToken() async {
    try {
      if (!await NotificationPrefs.notificationsEnabled()) {
        await unregisterDeviceToken();
        return;
      }

      await FirebaseMessaging.instance.requestPermission();

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await ApiClient.post('/device-tokens', {
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'sound_enabled': await NotificationPrefs.alertSoundEnabled(),
      });
    } catch (_) {
      // Not fatal — the app still works without push, and this is retried
      // on the next successful login.
    }
  }

  /// Tells the backend to stop sending this device push notifications for
  /// the currently logged-in user. Call this on logout, while the auth token
  /// is still saved, so a phone that's been logged out (or handed to someone
  /// else) doesn't keep receiving the previous account's alerts.
  static Future<void> unregisterDeviceToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await ApiClient.delete('/device-tokens', {'token': token});
    } catch (_) {
      // Not fatal — logout must still go through even if this fails (e.g.
      // no connectivity).
    }
  }

  static Future<void> playSiren() async {
    if (!await NotificationPrefs.alertSoundEnabled()) return;
    await _player.stop();
    await _player.play(AssetSource('audio/alarm.mp3'));
  }
}
