import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// The system-browser OAuth round-trip, abstracted so tests never launch a
/// real browser.
abstract class OAuthBrowser {
  /// Inputs: the authorization URL to open and the custom scheme the app
  /// registered for its redirect.
  /// Outputs: the full callback URL the browser was redirected to.
  Future<String> authenticate({required String url, required String callbackUrlScheme});
}

/// [OAuthBrowser] backed by `flutter_web_auth_2`'s system-browser handoff.
class FlutterWebAuthBrowser implements OAuthBrowser {
  const FlutterWebAuthBrowser();

  @override
  Future<String> authenticate({required String url, required String callbackUrlScheme}) {
    return FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackUrlScheme);
  }
}
