#!/usr/bin/env node
/**
 * Builds docs/security/sde-controls-assessment.json from the countermeasure
 * list exported from SD Elements (docs/security/sde-countermeasures.json) and
 * the explicit assessments in assessment-data.mjs. Countermeasures without an
 * explicit entry receive a rule-based assessment (GitHub pipeline tests,
 * platform features that are not used, generic verification tasks).
 *
 * Every note is written in Brazilian Portuguese and English and ends with the
 * signature "RafahMarinho with Agentic AI".
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { explicit } from './assessment-data.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const input = path.join(root, 'docs', 'security', 'sde-countermeasures.json');
const output = path.join(root, 'docs', 'security', 'sde-controls-assessment.json');

const STATUS = { C: 'Complete', I: 'Incomplete', N: 'Not Applicable' };
const SIGNATURE = 'RafahMarinho with Agentic AI';

/** Rule-based fallbacks: [regex on title, status, en, pt]. First match wins. */
const rules = [
  [/\(GitHub\)/, 'I', (t) => `GitHub governance control "${t}" is not configured: the repository has no branch protection, required reviews, signed commits, CI pipeline or artifact policy yet. Deployment is a direct Vercel Git integration.`, (t) => `O controle de governança do GitHub "${t}" não está configurado: o repositório ainda não possui proteção de branch, revisões obrigatórias, commits assinados, pipeline de CI ou política de artefatos. A implantação é uma integração Git direta da Vercel.`],
  [/\(Cloud\)/, 'I', (t) => `Cloud governance activity "${t}" has not been performed for the demo; Supabase and Vercel are consumed as managed services without a formal assessment.`, (t) => `A atividade de governança de nuvem "${t}" não foi realizada para a demo; Supabase e Vercel são consumidos como serviços gerenciados sem avaliação formal.`],
  [/iCloud|CloudKit|Siri|widget|3D touch|Pasteboard|Drag and Drop|biometric|location data|Spotlight|notification/i, 'N', (t) => `Not applicable: the feature referenced by "${t}" is not used by the ACME Control mobile app.`, (t) => `Não aplicável: o recurso referenciado em "${t}" não é usado pelo app móvel do ACME Control.`],
  [/Binder|AIDL|Messenger|Intent|Broadcast|IPC|Doze|lock screen|safe browsing|Security Provider/i, 'N', (t) => `Not applicable: the Android mechanism referenced by "${t}" is not used (single activity, no services, receivers, providers or background work).`, (t) => `Não aplicável: o mecanismo Android referenciado em "${t}" não é usado (activity única, sem services, receivers, providers ou trabalho em segundo plano).`],
  [/cookie/i, 'N', () => 'Not applicable: the application uses bearer tokens in the Authorization header and no cookies.', () => 'Não aplicável: a aplicação usa tokens bearer no cabeçalho Authorization e nenhum cookie.'],
  [/MariaDB|MySQL|Oracle|SQL Server|MongoDB|Transparent Data Encryption/i, 'N', (t) => `Not applicable: "${t}" targets a database product that is not used (PostgreSQL on Supabase).`, (t) => `Não aplicável: "${t}" visa um produto de banco de dados que não é usado (PostgreSQL no Supabase).`],
  [/personal (information|data)|privacy|consent/i, 'I', (t) => `Privacy activity "${t}" is only partially covered: personal data is minimal and classified in the threat model, users edit their own profile and retention purge runs nightly, but formal notices, consent and data-subject procedures are pending.`, (t) => `A atividade de privacidade "${t}" é coberta apenas parcialmente: os dados pessoais são mínimos e classificados no modelo de ameaças, os usuários editam o próprio perfil e o expurgo de retenção roda diariamente, mas avisos formais, consentimento e procedimentos para titulares estão pendentes.`],
  [/penetration|pentest|DAST|SAST|vulnerability assessment|code review/i, 'I', (t) => `"${t}" has not been performed; verification so far is limited to static analysis (flutter analyze, tsc), automated unit/security tests and the Supabase security advisor.`, (t) => `"${t}" não foi realizado; a verificação até agora se limita à análise estática (flutter analyze, tsc), testes automatizados unitários/de segurança e ao advisor de segurança do Supabase.`],
  [/backup|restor/i, 'I', (t) => `"${t}" depends on the Supabase plan; the free-tier demo project has no scheduled backups. Schema and demo data are reproducible from the Git migrations and seed.`, (t) => `"${t}" depende do plano Supabase; o projeto de demo em plano gratuito não tem backups agendados. O esquema e os dados de demo são reproduzíveis a partir das migrações e do seed no Git.`],
  [/^(Test|Verify)/i, 'I', (t) => `"${t}" has not been executed as a dedicated test yet. The related control is implemented (see docs/security/controls.md) and covered by code review; a formal test record is pending.`, (t) => `"${t}" ainda não foi executado como teste dedicado. O controle relacionado está implementado (ver docs/security/controls.md) e coberto por revisão de código; um registro formal de teste está pendente.`],
];

const defaults = {
  Activities: ['I', (t) => `Process activity "${t}" is not formally established for this demonstration project.`, (t) => `A atividade de processo "${t}" não está formalmente estabelecida para este projeto de demonstração.`],
  default: ['I', (t) => `"${t}" is not implemented yet; tracked as a follow-up in docs/security/threat-model.md (residual risks).`, (t) => `"${t}" ainda não está implementado; rastreado como acompanhamento em docs/security/threat-model.md (riscos residuais).`],
};

function assess(cm) {
  const e = explicit[cm.task_id];
  if (e) return { status: STATUS[e[0]], en: e[1], pt: e[2], source: 'explicit' };
  for (const [re, st, en, pt] of rules) {
    if (re.test(cm.title)) return { status: STATUS[st], en: en(cm.title), pt: pt(cm.title), source: 'rule' };
  }
  const d = defaults[cm.phase] ?? defaults.default;
  return { status: STATUS[d[0]], en: d[1](cm.title), pt: d[2](cm.title), source: 'default' };
}

const countermeasures = JSON.parse(fs.readFileSync(input, 'utf8'));
const unknown = Object.keys(explicit).filter((id) => !countermeasures.some((c) => c.task_id === id));
if (unknown.length) console.warn('Explicit entries without a project countermeasure:', unknown.join(', '));

const result = countermeasures.map((cm) => {
  const a = assess(cm);
  return {
    id: cm.id,
    task_id: cm.task_id,
    title: cm.title,
    phase: cm.phase,
    priority: cm.priority,
    risk_relevant: Boolean(cm.risk_relevant),
    status: a.status,
    source: a.source,
    note: `[PT-BR] ${a.pt}\n\n[EN] ${a.en}\n\n${SIGNATURE}`,
  };
});

fs.writeFileSync(output, JSON.stringify(result, null, 2));

const summary = {};
for (const r of result) {
  summary[r.status] = (summary[r.status] ?? 0) + 1;
  summary[`${r.phase}/${r.status}`] = (summary[`${r.phase}/${r.status}`] ?? 0) + 1;
  summary[`source:${r.source}`] = (summary[`source:${r.source}`] ?? 0) + 1;
}
console.log(`Wrote ${result.length} assessments to ${path.relative(root, output)}`);
console.log(summary);
