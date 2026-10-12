# ACME Control – Threat model

Companion to the SD Elements project **ACME Control - Water Treatment Supervisory System**
(business unit AcmeBank, application ACME Control, project id 29). The SD Elements survey
answers, the generated countermeasures and their statuses live in
[`sde-countermeasures.json`](sde-countermeasures.json) and
[`sde-controls-assessment.json`](sde-controls-assessment.json); the implementation map is in
[`controls.md`](controls.md).

## 1. System overview

ACME Control is a SCADA-style supervisory system for two fictional water-treatment plants.
It is a simulation: no PLC, fieldbus or physical equipment is connected and every external
integration (SMS to on-call, CMMS, historian, supervisor e-mail) is journaled instead of sent.

| Component | Technology | Trust level |
| --- | --- | --- |
| Operator app (web, Android, iOS) | Flutter / Dart, Material 3, Riverpod, go_router, supabase_flutter | Untrusted client |
| Command and simulation API | TypeScript, Hono, Vercel Functions (pnpm) | Trusted server, holds the Supabase service-role key |
| Data platform | Supabase: PostgreSQL + RLS, Auth (e-mail/password + recovery), Storage (private bucket), Realtime | Trusted platform, policies enforced in the database |
| Simulated integrations | In-process journal (`events` table, category `integration`) | n/a |

Survey answers that drive the countermeasure set: web application, web service, frontend, mobile
app (Android, iOS), uses a database (PostgreSQL), third-party libraries, network communication,
ICS/IACS with critical operations, consumes cloud services, TypeScript/JavaScript, HTML5, CORS,
JSON, reads/writes files, authentication for end users and server-to-server, change/forgot
password, authorization, session management, text input, multi-threading, temporary files,
file upload, diagnostic logging, random numbers, sends e-mail, HTTP, Latin America, personal
data, GitHub, static analysis, open-source security libraries, Burp Suite, MASVS level 1,
changes to authentication, session management, servers/frameworks, interfaces, user I/O,
transactions and processes.

## 2. Assets

| Asset | Why it matters |
| --- | --- |
| Process state and equipment commands | Wrong or unauthorised commands flood or drain tanks, trip pumps, raise false alarms |
| Setpoints | Control the automatic controller; governed by supervisor review |
| Alarm and event history, command log, security log | Operational and forensic record |
| User accounts, roles, sessions | Role decides what a person may operate, lock out, approve or inspect |
| Personal data | Names, e-mail addresses, phone numbers, avatars of plant staff |
| Maintenance photos / attachments | May show plant internals |
| Supabase service-role key, Vercel configuration | Full database access if leaked |

## 3. Actors and entry points

| Actor | Entry point | Capabilities |
| --- | --- | --- |
| Operator | App (web/mobile) | Operate pumps/valves, acknowledge alarms, write handovers, propose setpoints |
| Engineer | App | Operator capabilities + simulation control, work orders, lockout |
| Supervisor | App | Review setpoint proposals, acknowledge handovers, read the security log, simulation control |
| Maintenance | App | Work orders and equipment lockout; cannot operate the process |
| Anonymous Internet user | Supabase REST/Realtime/Storage endpoints, API URL, web app URL | Must get nothing beyond the sign-in page |
| Supabase / Vercel platform operators | Platform consoles | Out of scope (vendor assessment) |

Trust boundaries: browser/phone ↔ Supabase (anon key + user JWT, RLS); browser/phone ↔ API
(user JWT, role checks); API ↔ Supabase (service-role key, server side only).

## 4. Threats (STRIDE) and mitigations

| # | Threat | Category | Mitigation (see controls.md) |
| --- | --- | --- | --- |
| T-01 | Stolen or forged session token used to send commands | Spoofing | Supabase JWT verified server side on every API call (`requireAuth`), malformed tokens refused before any lookup, failed attempts throttled per IP and audited, PKCE auth flow, secure session storage on mobile, idle (30 min) and absolute (12 h) session timeouts, sign-out wipes caches |
| T-02 | Credential stuffing / brute force on sign-in | Spoofing | Supabase Auth rate limits, password policy (12+ chars, 3 character classes, deny-list, no e-mail fragments), consistent error messages, previous-login notification, leaked-password protection (dashboard setting, documented) |
| T-03 | Operator escalates to supervisor by editing `profiles.role` | Elevation | RLS + `protect_profile_update` trigger (role, e-mail and sign-in columns immutable for clients), role read server side from `profiles`, not from the JWT |
| T-04 | Maintenance role starts a pump through the REST API or the control API | Elevation | Equipment writes are not allowed for clients (no RLS insert/update policy); the API centralises authorization (`requireRole`/`assertRole`) and interlocks |
| T-05 | A supervisor approves their own setpoint proposal | Elevation / repudiation | Separation of duties enforced in `setpoints.ts` (self-review denied and audited) |
| T-06 | Client tampers with alarms, handovers or work orders (changes messages, rewrites history, back-dates) | Tampering | Column-level protection triggers: alarms can only move `active → acknowledged`; handovers follow draft → submitted → acknowledged with ownership checks; work-order ownership fields immutable; attachments validated |
| T-07 | Forged audit entries (`events` with a fake actor) | Repudiation | `events` insert policy restricts categories and forces `actor` to the caller's own name/e-mail; API-only `security_events` table readable only by supervisors |
| T-08 | Public photos / avatars enumerated by outsiders | Information disclosure | Bucket is private; reads need a signed URL issued to a signed-in user; uploads are path-scoped per user and per plant and limited to image/PDF types and 10 MB |
| T-09 | Anonymous access to tables or RPCs | Information disclosure / elevation | RLS on every table with `to authenticated` policies, `revoke all ... from anon`, demo-data and rate-limit functions executable only by `service_role`, `acme_role()` no longer SECURITY DEFINER |
| T-10 | API flooded with ticks/commands (denial of service, runaway simulation) | DoS | Database-backed fixed-window rate limits per user and route group with in-memory fallback, 16 KB body limit, JSON-only bodies, method allow-list, bounded simulation advance (≤ 4 h) and tick (≤ 30 s) |
| T-11 | Injection through command payloads, notes, justifications | Tampering | Strict zod schemas (`.strict()`, UUIDs, enumerations, bounded printable text), parameterised Supabase client, no dynamic SQL; database triggers re-check lengths |
| T-12 | Cross-site scripting / clickjacking of the web app | Tampering | Flutter renders to canvas (no HTML injection surface); CSP, `frame-ancestors 'none'`, `X-Frame-Options`, nosniff, HSTS, Referrer-Policy and Permissions-Policy set on the web app and API |
| T-13 | Cross-site request forgery against the API | Spoofing | Bearer tokens only (no cookies), CORS allow-list with explicit origins, JSON-only bodies |
| T-14 | Leaking internals through errors or logs | Information disclosure | Generic 500 message with request id, details only in server logs, no secrets or tokens logged, consistent 401 wording |
| T-15 | Service-role key leaks into the app bundle or repo | Information disclosure | Key only in Vercel/`.env` (git-ignored), app receives only the publishable key, env validation at startup, `.env.example` without secrets |
| T-16 | Password-recovery link abuse / open redirect | Spoofing | Supabase one-time PKCE recovery, redirect URLs allow-listed in the Supabase dashboard, deep link accepted only for `acmecontrol://auth/reset-password`, in-app routes validated (`from` must be an internal path) |
| T-17 | Unbounded history growth (trend samples, events) | DoS | `purge_history()` scheduled nightly with pg_cron (7 days of trends, 90 days of events, 365 days of security events), queries paginated/limited in the app |
| T-18 | Offline cache on a lost phone reveals process data | Information disclosure | Cache holds non-secret operational snapshots only, session stored in Keystore/Keychain, Android backups disabled, cleartext traffic disabled, cache cleared on sign-out |
| T-19 | Vulnerable dependencies | Tampering | `pnpm audit` clean (API), `flutter pub outdated` reviewed, versions pinned by lockfiles |
| T-20 | Loss of availability of the cloud platform | DoS | Simulation only; documented degraded mode (offline read-only view), Supabase backups (dashboard), no production SLA claimed |

## 5. Residual risks and out-of-scope items

* **No multi-factor authentication.** Supabase supports TOTP; it is not enabled in this demo
  (SD Elements T1 is reported as Incomplete).
* **Supabase dashboard settings** (minimum password length, leaked-password protection, redirect
  URLs, MFA) cannot be set from the repository; they are documented in the README and reported as
  Incomplete until configured.
* **No CI/CD pipeline, SAST/DAST, penetration test or formal code review** has been run; the
  corresponding Activities/Testing countermeasures are reported as Incomplete.
* **Mobile binary protection** (root/jailbreak detection, anti-debugging, integrity checks) is not
  implemented; obfuscation is documented as a build flag.
* **ICS-specific hardware controls** (watchdog timers, out-of-band channels, static network
  configuration, power supply) do not apply to a cloud-hosted simulation and are reported as Not
  Applicable with an explanation.
* The system handles a small amount of personal data of plant staff; privacy notices, consent and
  data-subject processes are only partially covered (profile edit, retention purge) and are
  reported accordingly.
