# ACME Control – Security controls map

Where each security requirement recommended by SD Elements is implemented. The SD Elements task
ids (`T…`) refer to the countermeasures of project 29; the full status list with bilingual notes
is generated into [`sde-controls-assessment.json`](sde-controls-assessment.json) by
`scripts/sde/build-assessment.mjs` and pushed with `scripts/sde/sync-sde-tasks.mjs`.

## Authentication and sessions

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Token verification on every API call, generic failure message, malformed tokens refused early | `api/src/lib/auth.ts` (`requireAuth`) | T8, T16, T2141 |
| Throttling of failed authentication per IP, security log entry | `api/src/lib/auth.ts` + `api/src/lib/ratelimit.ts` (`RATE_LIMITS.auth`) | T6, T144 |
| Password policy (12+ chars, 3 of 4 classes, deny-list, no e-mail fragment) | `app/lib/core/security.dart` (`validatePassword`), used by reset and change-password forms | T4, T7 (hashing by Supabase Auth) |
| Change password requires the current password (re-authentication) | `app/lib/services/auth_service.dart` (`changePassword`), Profile screen | T3 |
| Password recovery through one-time PKCE links, redirect allow-list | `app/lib/services/auth_service.dart`, Supabase dashboard (documented in README) | T2 |
| Idle timeout (configurable, default 30 min) and absolute timeout (12 h) | `app/lib/providers/session_guard.dart`, Settings → Security | T24, T25 |
| Sign-out clears session, offline cache and cached profile | `app/lib/providers/auth_providers.dart` (`signOutEverywhere`) | T26, T1540 |
| Encrypted session storage on Android/iOS (Keystore / Keychain) | `app/lib/services/secure_session_storage.dart` | T2167, T155 |
| Previous sign-in notification | DB trigger `track_sign_in` → `profiles.previous_sign_in_at`; shown after login and on the Profile page | T427 |
| Unique user id per person, no shared accounts | Supabase Auth users, demo accounts are personal | T135 |
| Demo credentials never shown unless `DEMO_MODE=true` | `app/lib/core/env.dart`, `app/lib/features/auth/login_screen.dart` | T61 |

## Authorization

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Role read from `profiles` server side, never trusted from the client | `requireAuth` | T18 |
| Centralised function-level checks (`requireRole`, `assertRole`), denials audited | `api/src/lib/auth.ts`, every route | T15, T2141, T16 |
| Row Level Security on every table; anonymous role revoked | `supabase/migrations/20261011000000_init.sql`, `20261012120000_security_controls.sql` | T19, T2619, T2617 |
| Clients cannot write equipment/process state/setpoints/commands; only the API can | No insert/update policies for those tables | T14 |
| State machines and ownership enforced in the database (alarms, handovers, work orders, profiles) | Triggers `protect_alarm_update`, `protect_handover_write`, `protect_maintenance_write`, `protect_profile_update` | T33, T67, T99 |
| Separation of duties: a supervisor cannot review their own proposal | `api/src/routes/setpoints.ts` | T2388 |
| Four-eyes workflow for setpoints (propose → supervisor review) | `setpoint_requests` table + API | T9 |
| Demo reset / seed functions only callable by the service role | Migration §9 | T2141 |
| Navigation and screens adapt to the role; route guard redirects | `app/lib/core/router.dart`, `app/lib/features/shell/navigation.dart` | T16 (defence in depth only) |

## Input validation and output handling

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Strict JSON schemas (UUIDs, enumerations, finite numbers, bounded printable text) | `api/src/lib/security.ts` (`parseJson`, `safeText`, `shortCode`), all routes | T31, T32, T34, T42, T569 |
| Body size limit (16 KB), JSON-only content type, method allow-list | `api/src/lib/security.ts` (`bodyGuard`, `methodAllowList`) | T65, T228 |
| Database-side length and structure checks (attachments, texts) | Migration triggers, `validate_attachments` | T31 |
| Client-side validation and max lengths on every form, text sanitisation | `app/lib/core/security.dart` (`sanitizeText`, limits) + forms | T31 |
| No SQL built from strings; Supabase client with bound parameters | `api/src/**` | T38/T101 (SQL injection) |
| Canvas-rendered Flutter UI (no DOM injection), CSP on the web app | `app/web/index.html`, `app/vercel.json` | T37, T331, T420 |
| Deep links accepted only for the exact recovery route | `app/lib/app.dart` | T265, T274 |

## Transport, headers and browser hardening

| Control | Implementation | SD Elements |
| --- | --- | --- |
| HTTPS everywhere (Supabase, Vercel); API refuses non-https Supabase URLs | `api/src/lib/env.ts` | T87, T2620, T2666 |
| HSTS, nosniff, `X-Frame-Options`, Referrer-Policy, Permissions-Policy, COOP, CSP, `Cache-Control: no-store` on API | `api/src/lib/security.ts`, `app/vercel.json` | T322, T435, T1873, T64, T119 |
| CORS allow-list of browser origins | `api/src/app.ts`, `CORS_ORIGINS` | T1192-related, T318 |
| Android: cleartext traffic disabled, network security config, backups disabled | `app/android/app/src/main/AndroidManifest.xml`, `res/xml/*.xml` | T173, T2167 |
| iOS: App Transport Security kept strict | `app/ios/Runner/Info.plist` | T173 |

## Files and storage

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Private bucket, signed URLs, authenticated reads only | Migration §5, `app/lib/services/storage_service.dart` | T2167, T214 |
| Upload paths scoped per user (`avatars/<uid>.<ext>`) and per plant (`maintenance/<plant>/…`), role check for maintenance uploads | Storage policies | T50, T53 (type/size limits) |
| MIME allow-list (png, jpeg, webp, pdf) and 10 MB limit enforced by the bucket | `storage.buckets` | T54, T129 |
| Attachment metadata validated in the database | `validate_attachments` | T1148 |

## Logging, monitoring and retention

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Security log: auth failures, authorization denials, rate limiting, commands, setpoint reviews, lockouts, simulation control | `api/src/lib/audit.ts` → `security_events` | T45, T71, T2602, T2622 |
| Security log readable by supervisors only, never writable by clients | RLS on `security_events`, Security page in the app | T349, T350 |
| Operational event journal with forced actor identity | `events` insert policy | T71 |
| Request ids on every response, correlated with server logs | `requestIdMiddleware` | T45 |
| No confidential data in logs (no tokens, passwords, keys) | Code review of `console.*`/`debugPrint` | T46, T229 |
| Nightly retention purge (trend 7 d, events 90 d, security 365 d) | `purge_history()` + pg_cron job `acme-control-purge-history` | T607, T735 |

## Availability

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Per-user / per-IP rate limits shared across function instances | `public.consume_rate_limit`, `api/src/lib/ratelimit.ts` | T1363, T537 |
| Bounded simulation steps and result sets | `sim.ts` schemas, `.limit()` in repositories | T2600 |
| Degraded mode: offline read-only view, control actions require a connection | `app/lib/providers/connectivity_providers.dart`, banners | T433 |
| Backups | Supabase daily backups (dashboard); documented | T364, T2623 |

## Secrets and configuration

| Control | Implementation | SD Elements |
| --- | --- | --- |
| Service-role key only on the server, validated at startup, never logged | `api/src/lib/env.ts`, `.env.example` | T249, T10, T2616 |
| App receives only the publishable key through `--dart-define-from-file` | `app/lib/core/env.dart` | T249 |
| Secure defaults (CORS not `*`, demo mode off, debug flags off in release) | `.env.example`, `env.example.json` | T2349, T456, T49 |
| Dependency audit | `pnpm audit` (clean), `flutter pub outdated` | T241, T370 |

## Verification performed locally

* `pnpm typecheck`, `pnpm test` (engine + HTTP security tests), `pnpm audit --prod`
* `flutter analyze`, `flutter test` (models, formatters, login screen, password policy, sanitiser)
* `flutter build web --release`
* Supabase security advisor: no errors after the migration (one informational notice on the
  policy-less `rate_limits` table, which is intentionally not exposed; leaked-password protection
  must be enabled in the dashboard)
