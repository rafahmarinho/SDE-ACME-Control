/**
 * Simulated external integrations. Nothing leaves the server: every "call" is
 * journaled as an `integration` event so the UI can show what a real deployment
 * would have sent (SMS to on-call, CMMS export, historian journaling, e-mail).
 */
import type { AlarmCondition, SimEvent } from '../sim/types.js';

const ON_CALL_NUMBER = '+1 555 0100';

export function onCallSms(alarm: AlarmCondition): SimEvent {
  return {
    category: 'integration',
    level: 'info',
    message: `Simulated SMS sent to on-call ${ON_CALL_NUMBER}: ${alarm.message}`,
    actor: 'system',
    data: { channel: 'sms', to: ON_CALL_NUMBER, code: alarm.code, severity: alarm.severity },
  };
}

export function historianJournal(count: number, simTime: string): SimEvent {
  return {
    category: 'integration',
    level: 'info',
    message: `Simulated historian export: ${count} samples journaled`,
    actor: 'system',
    data: { system: 'historian', samples: count, sim_time: simTime },
  };
}

export function cmmsSync(kind: 'lockout' | 'release' | 'work_order', tag: string, actor: string): SimEvent {
  const text =
    kind === 'lockout'
      ? `Simulated CMMS sync: lockout recorded for ${tag}`
      : kind === 'release'
        ? `Simulated CMMS sync: ${tag} returned to service`
        : `Simulated CMMS sync: work order exported for ${tag}`;
  return { category: 'integration', level: 'info', message: text, actor, data: { system: 'CMMS', kind, tag } };
}

export function supervisorEmail(subject: string, to: string, actor: string): SimEvent {
  return {
    category: 'integration',
    level: 'info',
    message: `Simulated e-mail to ${to}: ${subject}`,
    actor,
    data: { channel: 'email', to, subject },
  };
}
