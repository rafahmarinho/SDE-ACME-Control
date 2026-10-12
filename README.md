# ACME Control

Industrial supervisory system for a small water treatment plant: two tanks, three pumps, three valves,
level / pressure / flow instrumentation, alarms, trends, commands, setpoint governance, maintenance and
shift handover. One Supabase project is shared by the web app and the Android / iOS apps.

| Layer | Technology |
| --- | --- |
| App (web, Android, iOS) | Flutter · Dart · Material 3 · Riverpod · go_router · supabase_flutter · fl_chart |
| Command & simulation API | TypeScript · Hono · Vercel Functions · pnpm |
| Data, auth, files, realtime | Supabase (PostgreSQL + RLS, e-mail/password auth, Storage, Realtime) |

```
ACME Control/
├─ app/        Flutter application (lib/core, lib/models, lib/services, lib/providers, lib/features, lib/widgets)
├─ api/        TypeScript API: process engine, commands, scenarios, setpoint review, maintenance lockout,
│              security middleware (auth, rate limiting, audit log, hardened headers)
├─ supabase/   SQL migrations (schema, RLS, realtime, storage, demo-data generator, security controls) and seed
├─ docs/security/  Threat model, controls map and the SD Elements assessment (585 countermeasures)
├─ scripts/sde/    Builds the assessment and syncs statuses + bilingual notes to SD Elements
└─ SECURITY.md     Vulnerability reporting policy
```

Security documentation: [threat model](docs/security/threat-model.md), [controls map](docs/security/controls.md),
[SD Elements assessment](docs/security/sde-controls-assessment.json). See the [Security](#4-security) section below.

## What it does

* **Plants** – two demo plants (North River WTP `NR-01`, Lakeside WTP `LS-02`). Switch plant from the top bar.
* **Process overview** – animated 2.5D schematic (intake → P1 → V1 → T1 → P2 → V2 → treatment → T2 → P3 → V3 → network)
  with moving water in the pipes, tank fill levels, pump impellers, valve positions, pressures and flows. Tap a
  component to operate it. Phones get a vertical schematic with pinch-zoom and bottom tabs (Plant, Alarms, Assets, More).
* **Equipment** – searchable, filterable asset list and detail pages with parameters, related alarms, work orders
  and command history. Requested and actual state are always shown side by side.
* **Commands** – start/stop pumps, open/close valves, manual/automatic mode, trip reset. The API validates roles,
  modes and interlocks: a pump cannot run when its source tank is empty, the intake is lost or the equipment is
  locked out for maintenance. Rejections are recorded with a reason.
* **Process engine** – tanks fill and drain according to the real flows, pumps ramp up and down, valves travel,
  dry-run protection trips pumps, level alarms (L/LL/H/HH), overflow, network pressure, turbidity and chlorine
  are evaluated every tick. Automatic mode uses the level setpoints.
* **Alarms** – active / acknowledged / cleared with severity, acknowledge one or all, critical banner.
* **Trends** – 24 h of history per tag, 1 h / 6 h / 24 h ranges, multi-tag chart with normalisation.
* **Setpoints** – operators and engineers propose changes with a justification; supervisors approve or reject.
  Approved values are applied immediately and used by the controller.
* **Maintenance** – work orders with priority, assignee, schedule, photos (Supabase Storage), status workflow and
  equipment lockout (simulated CMMS sync).
* **Shift handover** – summary, open issues, checklist, submit and acknowledge workflow.
* **Simulation** (engineer / supervisor) – six scenarios, pause / resume / speed, advance by 1 min, 10 min or 1 h,
  live event inspector and a one-click reset of the demo data.
* **Roles** – operator, engineer, supervisor, maintenance. Navigation, actions, RLS policies and API checks adapt
  to the role.
* **Mobile behaviour** – touch-friendly forms, realtime updates paused in the background and resumed on return,
  offline read-only view of the last data (every dataset is cached), control actions require a connection.
* **Simulated integrations** – SMS to on-call for high/critical alarms, CMMS export for work orders and lockouts,
  historian journaling, supervisor e-mail for setpoint proposals. They appear as `integration` events.

## Deployed environment

| Component | Where |
| --- | --- |
| Web app | <https://acme-control.vercel.app> (Vercel project `acme-control`, root directory `app`) |
| API | <https://acmecontrol-api.vercel.app/api> (Vercel project `acme-control-api`, root directory `api`) |
| Supabase | project `acme-control`, ref `zwooklcgzlzrrcpduzra`, region São Paulo (`sa-east-1`) |
| Source | <https://github.com/rafahmarinho/ACME-Control> (pushes to `main` deploy both Vercel projects) |

The schema, demo data and demo accounts are already loaded in the Supabase project. Environment variables are set on
both Vercel projects, except the server key that only the project owner can read:

1. Supabase dashboard → Project Settings → API keys → copy the **service_role** key (or create a **secret key**,
   `sb_secret_…`) and add it to the Vercel project `acme-control-api` as `SUPABASE_SERVICE_ROLE_KEY`, then redeploy.
   Alternatively connect the Supabase project to the Vercel projects through the Supabase integration already installed
   on the Vercel team (Vercel → Integrations → Supabase); it syncs the key automatically.
2. Supabase dashboard → Authentication → URL Configuration: Site URL `https://acme-control.vercel.app`, redirect URLs
   `https://acme-control.vercel.app/#/reset-password` and `acmecontrol://auth/reset-password`.

## 1. Supabase

1. Create a project at <https://supabase.com> (free tier is enough). Note the **Project URL**, the **anon** key
   and the **service_role** key (Project Settings → API) and the **connection string** (Project Settings → Database).
2. Apply the schema and load the demo data. Either

   **a) with the API scripts (no extra tooling)**

   ```bash
   cd api
   pnpm install
   cp .env.example .env          # fill SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DATABASE_URL
   pnpm db:setup                 # runs supabase/migrations/*.sql then supabase/seed.sql
   ```

   **b) with the Supabase CLI**

   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push              # migrations
   supabase db query --file supabase/seed.sql
   ```

   or paste the two migration files and `seed.sql` into the SQL editor, in that order.

   If writing to `auth.users` is blocked on your project, create the accounts through the Auth admin API instead:
   `pnpm seed:users` (uses the service role key, then loads the demo data).

3. Authentication → URL configuration: set **Site URL** to your web URL (e.g. `http://localhost:3000` during
   development) and add the redirect URLs `http://localhost:3000/#/reset-password`,
   `https://<your-web-domain>/#/reset-password` and `acmecontrol://auth/reset-password` (mobile deep link).
   E-mail/password sign-in is enabled by default; disable "Confirm email" if you want new accounts to work without
   e-mail verification.
4. Realtime is enabled by the migration (`supabase_realtime` publication) and the `attachments` storage bucket is
   created with public read access.

Local alternative: `supabase start` uses `supabase/config.toml`, applies the migrations and runs `seed.sql`.

5. Security settings (Authentication → Providers → Email / Authentication → Settings): set the **minimum password
   length to 12**, enable **leaked password protection** (HaveIBeenPwned check) and, if you want a second factor for
   supervisors and engineers, enable **TOTP MFA**. The app already enforces the password policy (12+ characters,
   three character classes, deny-list) on the client; these settings make the server enforce it too.
6. The migration `20261012120000_security_controls.sql` makes the `attachments` bucket **private**, adds the
   `security_events` audit table, the `rate_limits` table used by the API, column-protection triggers and a nightly
   `purge_history()` job (pg_cron, trends 7 days / events 90 days / security events 365 days). If pg_cron is not
   available on your plan, call `select public.purge_history();` from an external scheduler.

### Demo accounts (password `Acme1234!`)

The demo accounts share one documented password so the demo can be explored. Before any real deployment, delete them
or rotate their passwords (Authentication → Users). The sign-in page only shows the demo-account shortcuts when the
app is built with `DEMO_MODE=true`.

| E-mail | Name | Role |
| --- | --- | --- |
| operator@acme.demo | Dana Reyes | Operator – operates equipment, acknowledges alarms, writes handovers, proposes setpoints |
| engineer@acme.demo | Marcus Chen | Engineer – everything an operator can do, plus simulation control and work orders |
| supervisor@acme.demo | Priya Natarajan | Supervisor – reviews setpoint proposals, acknowledges handovers, simulation control |
| maintenance@acme.demo | Tom Okafor | Maintenance – work orders and equipment lockout; cannot operate the process |

## 2. API (TypeScript on Vercel)

```bash
cd api
pnpm install
cp .env.example .env     # SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (server side only)
pnpm dev                 # http://localhost:3001/api  (GET /api/health)
pnpm test                # engine unit tests + HTTP security tests (headers, verbs, body limits, CORS, auth, rate limiter)
pnpm typecheck
pnpm audit --prod        # dependency vulnerabilities (clean at the time of writing)
```

Every request gets an `X-Request-Id`; errors return `{error, message, requestId}` without internals. Requests are
throttled per user and route group (commands 40/min, simulation 20/min, ticks 120/min, setpoints 30/min, maintenance
30/min, failed authentications 30/min per IP) and answered with `429` + `Retry-After` when exceeded. Authentication
failures, authorization denials, commands, setpoint reviews, lockouts and simulation control are written to the
`security_events` table (visible to supervisors on the **Security** page). `CORS_ORIGINS` must list the web app
origins; `*` works for quick demos but is logged as a warning.

Endpoints (all need `Authorization: Bearer <supabase access token>`):

| Method & path | Who | Purpose |
| --- | --- | --- |
| `POST /api/commands` | operator, engineer, supervisor | `{plantId, equipmentId, type: start\|stop\|open\|close\|set_mode\|reset, value?}` |
| `POST /api/equipment/:id/maintenance` | maintenance, engineer, supervisor | `{underMaintenance, note?}` lockout / return to service |
| `POST /api/sim/tick` | any | advance the plant by the real elapsed time (called by connected clients) |
| `POST /api/sim/advance` | engineer, supervisor | `{plantId, seconds}` jump the simulation forward |
| `POST /api/sim/scenario` | engineer, supervisor | `{plantId, scenario}` load a scenario |
| `POST /api/sim/control` | engineer, supervisor | `{plantId, running, speed?}` pause / resume / speed |
| `POST /api/sim/reset` | engineer, supervisor | rebuild the demo data (`seed_demo_data()`) |
| `GET /api/sim/scenarios` | any | scenario catalogue |
| `POST /api/setpoints/requests` | operator, engineer, supervisor | propose a setpoint change |
| `POST /api/setpoints/requests/:id/review` | supervisor | `{decision: approve\|reject, note?}` |

### Deploy the API to Vercel

```bash
cd api
npx vercel login
npx vercel link                       # create / select the Vercel project
npx vercel env add SUPABASE_URL
npx vercel env add SUPABASE_SERVICE_ROLE_KEY
npx vercel env add CORS_ORIGINS       # e.g. https://acme-control.vercel.app  (or *)
pnpm deploy                           # = vercel --prod
```

The function entry is `api/index.ts` (Hono via `hono/vercel`); `vercel.json` rewrites `/api/*` to it. The API
URL becomes `https://<api-project>.vercel.app/api`. Pushing the `api/` folder to a Git repository connected to
Vercel deploys automatically (set the project root directory to `api`).

## 3. Flutter app

Requirements: Flutter stable 3.35 or newer (built and tested with 3.47 / Dart 3.13) with web, Android and iOS
tooling (`flutter doctor`).

```bash
cd app
cp env.example.json env.json          # SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL, WEB_APP_URL, DEMO_MODE
flutter pub get
flutter run -d chrome --web-port 3000 --dart-define-from-file=env.json
```

`API_BASE_URL` is `http://localhost:3001/api` with `pnpm dev`, or `https://<api-project>.vercel.app/api`
(on the Android emulator use `http://10.0.2.2:3001/api`, on a physical phone the LAN IP of your machine).
`SUPABASE_ANON_KEY` accepts the project's publishable key (`sb_publishable_…`) or the legacy anon JWT.
`WEB_APP_URL` is where the web app is served (used in password-recovery links). `DEMO_MODE=true` shows the
demo-account shortcuts on the sign-in page (keep it `false` for real deployments). Configuration is injected at build
time with `--dart-define-from-file`; never put the service role key in the app.

Session security: the session is stored in the Android Keystore / iOS Keychain (`flutter_secure_storage`), the app
signs the user out after 30 minutes without interaction (configurable in Settings → Security) or 12 hours after
sign-in, and sign-out wipes the offline cache. Password changes require the current password. Supervisors see the
**Security** page with the audit log. For store builds add `--obfuscate --split-debug-info=build/symbols` to the
`flutter build apk|appbundle|ipa` commands.

Other useful commands:

```bash
flutter analyze
flutter test
flutter run -d <android-device-id> --dart-define-from-file=env.json
flutter run -d <ios-simulator-id> --dart-define-from-file=env.json
```

### Deploy the web app to Vercel

Option A – build locally and upload the static output:

```bash
cd app
flutter build web --release --dart-define-from-file=env.json
npx vercel --prod build/web           # answer "no" to the framework questions; it is a static site
```

Option B – let Vercel build it: create a Vercel project with root directory `app`. `app/vercel.json` runs
`scripts/vercel-build.sh`, which clones the Flutter SDK and runs `flutter build web`. Add the environment variables
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL` and `WEB_APP_URL` to the project.

After deploying, add the web URL to the Supabase redirect URLs (see step 1.3) and, if the API uses a restricted
`CORS_ORIGINS`, add the web origin there too.

### Android package (APK / App Bundle)

```bash
cd app
flutter build apk --release --dart-define-from-file=env.json          # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release --dart-define-from-file=env.json    # build/app/outputs/bundle/release/app-release.aab
```

* Application id: `com.acme.control` (`android/app/build.gradle.kts`).
* The manifest declares the `INTERNET` permission and the `acmecontrol://auth/...` deep link used by password
  recovery (debug builds also allow plain-http traffic to a local API). The camera and photo picker come from `image_picker` (no extra permissions on Android 13+).
* For store releases create a keystore (`keytool -genkey -v -keystore ~/acme-release.jks -alias acme -keyalg RSA
  -keysize 2048 -validity 10000`), reference it from `android/key.properties` and switch `signingConfig` in
  `android/app/build.gradle.kts` from the debug key to the release key.

### iOS package (IPA)

```bash
cd app
flutter build ios --release --dart-define-from-file=env.json          # requires macOS + Xcode
flutter build ipa --release --dart-define-from-file=env.json          # build/ios/ipa/*.ipa for TestFlight / App Store
```

* Bundle id: `com.acme.control`. Open `ios/Runner.xcworkspace` once in Xcode to select your team / signing.
* `ios/Runner/Info.plist` declares the `acmecontrol` URL scheme and the camera / photo library usage descriptions.
* `cd ios && pod install` if CocoaPods reports missing pods.

## 4. Security

The threat model was built with **SD Elements** (business unit AcmeBank → application ACME Control → project
*ACME Control - Water Treatment Supervisory System*, id 29). The survey describes the stack above; SD Elements
generated 585 countermeasures (93 risk-relevant). Each one was assessed against the code and recorded with a note in
Brazilian Portuguese and English signed "RafahMarinho with Agentic AI".

| Document | Content |
| --- | --- |
| [docs/security/threat-model.md](docs/security/threat-model.md) | Assets, actors, trust boundaries, STRIDE threats and mitigations, residual risks |
| [docs/security/controls.md](docs/security/controls.md) | Where each control lives in the code (API, database, app) |
| [docs/security/sde-countermeasures.json](docs/security/sde-countermeasures.json) | Countermeasures exported from SD Elements |
| [docs/security/sde-controls-assessment.json](docs/security/sde-controls-assessment.json) | Status + bilingual note per countermeasure |
| [SECURITY.md](SECURITY.md) | How to report a vulnerability |

To rebuild the assessment and push it to SD Elements:

```bash
node scripts/sde/build-assessment.mjs                      # regenerates sde-controls-assessment.json
SDE_API_KEY=<token> SDE_PROJECT_ID=29 node scripts/sde/sync-sde-tasks.mjs   # PATCH status + POST note per task
```

Controls implemented in this release (details in controls.md): server-side token verification with generic
failures and per-IP throttling; centralised role checks with audited denials; separation of duties on setpoint
review; strict JSON schemas, body size/verb/content-type guards; hardened headers (HSTS, CSP, nosniff, DENY,
no-store); CORS allow-list; database-backed rate limits; `security_events` audit log readable by supervisors;
RLS on every table with anonymous access revoked; column-protection and state-machine triggers; private storage
with signed URLs and path-scoped uploads; nightly data retention purge; password policy and change-password
re-authentication; idle/absolute session timeouts; encrypted session storage on mobile; CSP on the web app;
Android backups and cleartext traffic disabled; previous-sign-in notification; demo credentials gated by
`DEMO_MODE`.

Known gaps (reported as Incomplete in SD Elements): no MFA, no CI pipeline / SAST / DAST / pentest / formal code
review, no backups on the free Supabase plan, Supabase network restrictions not configured, no root/jailbreak or
anti-tampering checks, privacy notices and consent not implemented, demo accounts with a shared password.

## Main flows to check

1. Sign in as **operator**. Overview shows plant KPIs, the top bar shows **Live** and the simulation clock advances.
2. Process → tap **P1**. It is in automatic mode; switch to **Manual**, press **Start**: requested = Run, actual goes
   Starting → Running, V1 opens (auto) and T1 fills. Switch back to **Automatic** and watch the controller stop P1
   when T1 reaches the stop setpoint.
3. Simulation (as **engineer**) → load **Intake failure**: P1 trips with a dry-run fault, `INTAKE_UNAVAILABLE` and
   `P1_TRIP` alarms appear, the SMS integration event is journaled. Advance **+10 min** and watch T1 drain and P2 stop.
   Load **Normal operation** to recover, then **Reset** to rebuild everything.
4. As **maintenance** lock out P2 from its equipment page; a start command from the operator is rejected with
   "under maintenance" and appears in the command log. Create a work order with a photo; the CMMS sync event appears.
5. As **engineer** propose `T2_START` 45 → 50 % on the Setpoints page; as **supervisor** approve it and see the value
   change and the event.
6. Acknowledge alarms, write a shift handover as **operator** and acknowledge it as **supervisor**.
7. Reload the page: everything persists. Turn the network off on a phone: the offline banner appears, the latest
   data stays visible, control buttons are disabled; turn it back on and updates resume.
8. Security: as **supervisor** open **Security** and see the audit entries produced by steps 2–6 (commands,
   setpoint review, lockout, rejected command). Change your password on the Profile page (current password
   required, policy enforced). Set the idle timeout to 5 minutes in Settings → Security and wait: the app signs you
   out with an explanation. Sign in as **maintenance** and try `POST /api/commands` with the session token: the API
   answers 403 and the denial appears in the security log.

## Notes

* The process advances while at least one client is open (each client requests a tick every few seconds; the
  `claim_tick` RPC guarantees a single advance per interval). Use the Simulation page to jump forward in time.
* Trend samples, alarms raised by the engine and simulation events use **simulated time**; user actions use wall time.
* Everything in the UI, reports and sample data is in English.
