export const PROTOCOL_VERSION = 1;
export const TICK_RATE = 60;
export const SNAPSHOT_RATE = 20;
export const DT = 1 / TICK_RATE;

export const FIELD = { width: 960, height: 540 } as const;
export const BALL_RADIUS = 14;
export const HOLE = { x: 820, y: 270, radius: 24, maxEntrySpeed: 95 } as const;
export const MAX_SHOT_POWER = 1;
export const SHOT_SPEED = 560;
export const LINEAR_DAMPING = 1.45;
export const WALL_RESTITUTION = 0.82;
export const BALL_RESTITUTION = 0.9;
export const STOP_SPEED = 1.5;

export type PlayerState = {
  id: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  shots: number;
  finished: boolean;
  connected: boolean;
};

export type Snapshot = {
  type: 'snapshot';
  tick: number;
  serverTime: number;
  roomId: string;
  players: PlayerState[];
};
