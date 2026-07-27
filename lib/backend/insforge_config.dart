/// Public InsForge project base URL -- safe to hardcode, not a secret; the
/// app needs no API key, only the user's own JWT once signed in.
const insforgeBaseUrl = 'https://5e3smxnc.us-east.insforge.app';

/// Custom URL scheme this app registers so the system browser can hand the
/// OAuth authorization result back to the app.
const oauthCallbackUrlScheme = 'bardizz';

/// Full redirect URI passed to InsForge's OAuth endpoint.
const oauthRedirectUri = '$oauthCallbackUrlScheme://auth/callback';
