# Security policy

ACME Control is a demonstration system. It still follows a defined process for security reports.

## Reporting a vulnerability

* E-mail **security@acme.demo** (fictional contact for this demo project) or open a private
  security advisory on the GitHub repository.
* Include the affected component (app, API, database policies), steps to reproduce and the impact.
* You will receive an acknowledgement within 2 business days and a status update every 7 days
  until the issue is closed.
* Please do not test against the shared demo Supabase project with destructive payloads; use a
  local stack (`supabase start`) instead.

## Supported versions

Only the `main` branch is supported. Security fixes are released as a new deployment of the web
app and API on Vercel and as a new mobile build; the change summary is kept in the Git history.

## Security documentation

* Threat model: [`docs/security/threat-model.md`](docs/security/threat-model.md)
* Controls map: [`docs/security/controls.md`](docs/security/controls.md)
* SD Elements assessment: [`docs/security/sde-controls-assessment.json`](docs/security/sde-controls-assessment.json)
