#!/usr/bin/env node
/**
 * Pushes the local assessment (docs/security/sde-controls-assessment.json) to
 * SD Elements: sets the status of every countermeasure and adds the bilingual
 * note. Idempotent for statuses; notes are only added when the same text is
 * not already present.
 *
 * Usage:
 *   SDE_API_KEY=... [SDE_HOST=sde-ent-echo.sdelab.net] [SDE_PROJECT_ID=29] node scripts/sde/sync-sde-tasks.mjs [--dry-run] [--only T1,T2]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const assessmentPath = path.join(root, 'docs', 'security', 'sde-controls-assessment.json');

const API_KEY = process.env.SDE_API_KEY;
const HOST = process.env.SDE_HOST ?? 'sde-ent-echo.sdelab.net';
const PROJECT = process.env.SDE_PROJECT_ID ?? '29';
const dryRun = process.argv.includes('--dry-run');
const onlyArg = process.argv.find((a) => a.startsWith('--only='));
const only = onlyArg ? new Set(onlyArg.slice(7).split(',')) : null;

if (!API_KEY && !dryRun) {
  console.error('SDE_API_KEY is required (create one in SD Elements > My Settings > API tokens).');
  process.exit(1);
}

const STATUS_IDS = { Complete: 'TS1', Incomplete: 'TS2', 'Not Applicable': 'TS3' };

/** @type {{id:string, task_id:string, title:string, status:string, note:string}[]} */
const assessment = JSON.parse(fs.readFileSync(assessmentPath, 'utf8'));

async function api(method, endpoint, body) {
  const res = await fetch(`https://${HOST}/api/v2${endpoint}`, {
    method,
    headers: {
      Authorization: `Token ${API_KEY}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text.slice(0, 200) };
  }
  return { status: res.status, json };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function withRetry(fn, label) {
  for (let attempt = 1; attempt <= 4; attempt++) {
    const r = await fn();
    if (r.status < 500 && r.status !== 429) return r;
    console.warn(`  ${label}: HTTP ${r.status}, retry ${attempt}`);
    await sleep(500 * attempt);
  }
  return fn();
}

async function main() {
  const items = assessment.filter((a) => !only || only.has(a.task_id));
  console.log(`Syncing ${items.length} countermeasures to project ${PROJECT} on ${HOST}${dryRun ? ' (dry run)' : ''}`);
  const counts = { status: 0, notes: 0, skippedNotes: 0, errors: 0 };

  for (let i = 0; i < items.length; i++) {
    const a = items[i];
    const statusId = STATUS_IDS[a.status];
    if (!statusId) {
      console.error(`Unknown status "${a.status}" for ${a.id}`);
      counts.errors++;
      continue;
    }
    if (dryRun) continue;

    const s = await withRetry(() => api('PATCH', `/projects/${PROJECT}/tasks/${a.id}/`, { status: statusId }), `${a.id} status`);
    if (s.status === 200) counts.status++;
    else {
      counts.errors++;
      console.error(`${a.id}: status update failed (${s.status}) ${JSON.stringify(s.json).slice(0, 160)}`);
    }

    const existing = await withRetry(() => api('GET', `/projects/${PROJECT}/tasks/${a.id}/notes/`), `${a.id} notes`);
    const notes = existing.json?.results ?? [];
    const already = notes.some((n) => (n.text ?? '').trim() === a.note.trim());
    if (already) {
      counts.skippedNotes++;
    } else {
      const n = await withRetry(() => api('POST', `/projects/${PROJECT}/tasks/${a.id}/notes/`, { text: a.note }), `${a.id} note`);
      if (n.status === 201 || n.status === 200) counts.notes++;
      else {
        counts.errors++;
        console.error(`${a.id}: note failed (${n.status}) ${JSON.stringify(n.json).slice(0, 160)}`);
      }
    }
    if ((i + 1) % 25 === 0 || i === items.length - 1) console.log(`[${i + 1}/${items.length}] ${a.id} ${a.status}`);
    await sleep(60);
  }
  console.log('Done', counts);
  if (counts.errors) process.exitCode = 1;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
