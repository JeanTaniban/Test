import type { PlayerState, Snapshot } from './game';

export type JoinMessage = {
  type: 'join';
  protocol: number;
  roomId: string;
  playerToken: string;
};

export type ShootMessage = {
  type: 'shoot';
  sequence: number;
  angle: number;
  power: number;
};

export type PingMessage = { type: 'ping'; clientTime: number };
export type ClientMessage = JoinMessage | ShootMessage | PingMessage;

export type WelcomeMessage = {
  type: 'welcome';
  playerId: string;
  roomId: string;
  state: PlayerState[];
};

export type ServerMessage =
  | WelcomeMessage
  | Snapshot
  | { type: 'pong'; clientTime: number; serverTime: number }
  | { type: 'error'; code: string; message: string };

export function parseClientMessage(raw: string): ClientMessage | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== 'object') return null;
  const v = value as Record<string, unknown>;
  if (v.type === 'join') {
    if (
      typeof v.protocol === 'number' &&
      typeof v.roomId === 'string' &&
      /^[A-Za-z0-9_-]{1,32}$/.test(v.roomId) &&
      typeof v.playerToken === 'string' &&
      v.playerToken.length >= 8 && v.playerToken.length <= 128
    ) return value as JoinMessage;
  }
  if (v.type === 'shoot') {
    if (
      Number.isInteger(v.sequence) && (v.sequence as number) >= 0 &&
      typeof v.angle === 'number' && Number.isFinite(v.angle) &&
      typeof v.power === 'number' && Number.isFinite(v.power)
    ) return value as ShootMessage;
  }
  if (v.type === 'ping' && typeof v.clientTime === 'number' && Number.isFinite(v.clientTime)) {
    return value as PingMessage;
  }
  return null;
}
