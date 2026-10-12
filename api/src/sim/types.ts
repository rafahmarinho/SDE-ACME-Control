export type EquipmentType = 'pump' | 'valve' | 'tank' | 'sensor';
export type EquipmentMode = 'manual' | 'auto';
export type AlarmSeverity = 'low' | 'medium' | 'high' | 'critical';
export type UserRole = 'operator' | 'engineer' | 'supervisor' | 'maintenance';

export interface EquipmentRow {
  id: string;
  plant_id: string;
  tag: string;
  name: string;
  type: EquipmentType;
  area: string | null;
  mode: EquipmentMode;
  /** pumps: run | stop ; valves: open | close ; tanks/sensors: n/a */
  requested_state: string;
  /** pumps: stopped | starting | running | stopping | tripped | maintenance ; valves: closed | opening | open | closing | maintenance */
  actual_state: string;
  /** valve % open, pump speed %, tank level % */
  position: number;
  under_maintenance: boolean;
  fault: string | null;
  interlock: string | null;
  runtime_hours: number;
  starts_count: number;
  params: Record<string, any>;
  sort_order: number;
}

export interface TankState {
  level: number;
  volume: number;
  capacity: number;
  inflow: number;
  outflow: number;
}

export interface Conditions {
  source_available: boolean;
  demand_factor: number;
  demand_nominal: number;
  demand_m3h: number;
  sensor_faults: string[];
  overflow_m3h?: number;
  last_trend_at?: string;
}

export interface ProcessStateRow {
  plant_id: string;
  scenario: string;
  sim_time: string;
  last_tick_at: string;
  speed: number;
  running: boolean;
  values: Record<string, number>;
  tanks: Record<string, TankState>;
  conditions: Conditions;
}

export interface AlarmCondition {
  code: string;
  tag: string;
  severity: AlarmSeverity;
  message: string;
  active: boolean;
  value?: number;
}

export interface SimEvent {
  category: 'command' | 'alarm' | 'simulation' | 'maintenance' | 'setpoint' | 'handover' | 'integration' | 'system' | 'control';
  level: 'info' | 'warning' | 'error';
  message: string;
  actor: string;
  data?: Record<string, unknown>;
}

export interface EngineContext {
  equipment: EquipmentRow[];
  setpoints: Record<string, number>;
  state: ProcessStateRow;
}

export interface StepResult {
  alarms: AlarmCondition[];
  events: SimEvent[];
}

export const TREND_TAGS = ['LT1', 'LT2', 'FT1', 'FT2', 'FT3', 'PT1', 'PT2', 'PT3', 'TU1', 'CL1'] as const;
