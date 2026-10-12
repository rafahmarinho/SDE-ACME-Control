# ACME Control - Flutter app

See the [project README](../README.md) for setup, configuration (env.json), running on web / Android / iOS,
and deployment instructions.

## Build-time configuration (`env.json`)

Copy `env.example.json` to `env.json` and pass it with `--dart-define-from-file=env.json`.

| Key | Purpose |
| --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Supabase project (publishable / anon key). |
| `API_BASE_URL` | Control API (Hono). |
| `WEB_APP_URL` | Public URL of the web app, used in password-recovery e-mails. |
| `DEMO_MODE` | `"true"` shows the demo-account shortcuts on the sign-in page. Default `false`: production builds never advertise shared credentials. |
| `DEMO_PASSWORD` | Optional password pre-filled by the demo chips (demo builds only). Empty by default so no credential is compiled into the app by accident. |

On Vercel, `scripts/vercel-build.sh` reads the same names from the project's environment variables (`DEMO_MODE` defaults to `false`).

## Security controls

- **Password policy** (`lib/core/security.dart`): at least 12 characters (max 128), three of four character classes, no e-mail local part, small deny-list. Applied on password reset and on the Profile page's "Change password" card (which re-authenticates with the current password first). Unit tests in `test/security_test.dart`.
- **Session hardening**: on Android / iOS the Supabase session lives in the platform secure store (`flutter_secure_storage`, `lib/services/secure_session_storage.dart`); web keeps the supabase_flutter default. `lib/providers/session_guard.dart` signs the user out after the configurable idle time (Settings > Security, 5-240 min, default 30) or 12 hours after sign-in, and the login page explains why (`/login?reason=idle|expired`). Signing out always clears the offline cache (`signOutEverywhere`).
- **Sign-in visibility**: "Previous sign-in" is shown once after sign-in and on the Profile page (`profiles.last_sign_in_at` / `previous_sign_in_at`, maintained server-side). Sign-ins and password changes are journaled in `events` (category `auth`).
- **Private storage**: the `attachments` bucket is private. Profiles and work orders store storage *paths* (`avatars/<uid>.<ext>`, `maintenance/<plant>/<file>`); `lib/services/storage_service.dart` resolves them to one-hour signed URLs (cached) and `StorageImage` / `UserAvatar` render them, with placeholders while offline. Legacy rows holding a public URL are still understood.
- **Input validation**: every free-text field has a hard `maxLength` and is passed through `sanitizeText` before it is sent (control characters stripped, newlines collapsed).
- **Error messages**: authentication failures map to fixed texts ("Incorrect e-mail or password.", "Sign-in failed. Please try again."); raw server messages are never shown.
- **Security audit log**: supervisors get a "Security" page (`/security`) listing the latest 200 `security_events` rows with search, outcome filters and request details.
- **Platform hardening**: Android disables backups and cleartext traffic (`network_security_config.xml`; debug builds re-allow plain http to local hosts only), iOS has `NSAllowsArbitraryLoads=false`, the web build ships a Content-Security-Policy meta tag and `vercel.json` sends CSP, HSTS, COOP, Referrer-Policy, Permissions-Policy, `X-Frame-Options` and `X-Content-Type-Options` headers. Deep links are only honoured for the exact `acmecontrol://auth/reset-password` callback.

## Checks

```
flutter analyze
flutter test
flutter build web --release --dart-define-from-file=env.json
```
