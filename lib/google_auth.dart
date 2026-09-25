// "Sign in with Google": runs the native Google account picker, sends the
// resulting ID token to the backend's POST /auth/google (which verifies it
// directly with Google and logs in or creates the account), and stores the
// returned Sanctum token + user — mirroring what the normal /login flow
// does in main.dart. main.dart decides where to navigate afterward.

import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';
import 'main.dart' show applyUserFromJson;

class GoogleAuthResult {
  final bool success;
  final String? errorMessage;
  const GoogleAuthResult.success()
      : success = true,
        errorMessage = null;
  const GoogleAuthResult.failure(this.errorMessage) : success = false;
}

class GoogleAuth {
  // The Web Client ID from Firebase (Authentication > Sign-in method >
  // Google > Web SDK configuration) — required so google_sign_in returns
  // an ID token the backend can verify. Must match GOOGLE_OAUTH_CLIENT_ID
  // in the backend's .env.
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '544408135182-qbtvp3vqs8ef3korcbggb6sfvb0ieof6.apps.googleusercontent.com',
  );

  /// Runs the native Google sign-in flow and logs into the backend. Returns
  /// null if the user closes the account picker without choosing one (not
  /// an error — the caller should just do nothing in that case).
  static Future<GoogleAuthResult?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return null;

      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        return const GoogleAuthResult.failure(
            'Could not get a Google sign-in token.');
      }

      final res = await ApiClient
          .post('/auth/google', {'id_token': idToken}, auth: false);
      await TokenStorage.save(res['token'] as String);
      applyUserFromJson(res['user'] as Map<String, dynamic>);

      return const GoogleAuthResult.success();
    } on ApiException catch (e) {
      return GoogleAuthResult.failure(e.message);
    } catch (_) {
      return const GoogleAuthResult.failure(null);
    }
  }
}
