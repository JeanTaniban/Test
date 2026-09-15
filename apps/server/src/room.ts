import { randomUUID } from 'node:crypto';
import type WebSocket from 'ws';
import {
  DT, HOLE, MAX_SHOT_POWER, SHOT_SPEED, SNAPSHOT_RATE, TICK_RATE,
  type PlayerState, type ShootMessage, type Snapshot,
} from '../../../packages/shared/src/index';
import { integratePlayer, isInHole, resolveBallCollision, resolveWalls } from './physics';

export type PlayerRuntime = {
  token: string;
  state: PlayerState;
  socket?: WebSocket;
  lastSequence: number;
  disconnectedAt?: number;
};

export class GameRoom {
  readonly players = new Map<string, PlayerRuntime>();
  tick = 0;
  private accumulator = 0;

  constructor(public readonly id: string) {}

  join(token: string, socket?: WebSocket): PlayerRuntime {
    const existing = [...this.players.values()].find((p) => p.token === token);
    if (existing) {
      existing.socket = socket;
      existing.state.connected = true;
      existing.disconnectedAt = undefined;
      return existing;
    }
    const index = this.players.size;
    const state: PlayerState = {
      id: randomUUID(),
      x: 100 + (index % 4) * 38,
      y: 220 + Math.floor(index / 4) * 38,
      vx: 0, vy: 0, shots: 0, finished: false, connected: true,
    };
    const runtime = { token, state, socket, lastSequence: -1 };
    this.players.set(state.id, runtime);
    return runtime;
  }

  disconnect(playerId: string): void {
    const p = this.players.get(playerId);
    if (!p) return;
    p.socket = undefined;
    p.state.connected = false;
    p.disconnectedAt = Date.now();
  }

  shoot(playerId: string, msg: ShootMessage): boolean {
    const p = this.players.get(playerId);
    if (!p || p.state.finished) return false;
    if (msg.sequence <= p.lastSequence) return false;
    if (!Number.isFinite(msg.angle) || !Number.isFinite(msg.power)) return false;
    if (msg.power <= 0 || msg.power > MAX_SHOT_POWER) return false;
    p.lastSequence = msg.sequence;
    p.state.shots += 1;
    const speed = SHOT_SPEED * msg.power;
    p.state.vx += Math.cos(msg.angle) * speed;
    p.state.vy += Math.sin(msg.angle) * speed;
    return true;
  }

  step(dt = DT): void {
    const list = [...this.players.values()].map((p) => p.state);
    for (const p of list) { integratePlayer(p, dt); resolveWalls(p); }
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        resolveBallCollision(list[i]!, list[j]!);
      }
    }
    for (const p of list) {
      if (!p.finished && isInHole(p)) {
        p.finished = true;
        p.x = HOLE.x; p.y = HOLE.y; p.vx = 0; p.vy = 0;
      }
    }
    this.tick += 1;
    this.accumulator += SNAPSHOT_RATE;
  }

  shouldSnapshot(): boolean {
    if (this.accumulator >= TICK_RATE) {
      this.accumulator -= TICK_RATE;
      return true;
    }
    return false;
  }

  snapshot(): Snapshot {
    return {
      type: 'snapshot', tick: this.tick, serverTime: Date.now(), roomId: this.id,
      players: [...this.players.values()].map((p) => ({ ...p.state })),
    };
  }

  cleanupDisconnected(graceMs = 15_000): void {
    const now = Date.now();
    for (const [id, p] of this.players) {
      if (p.disconnectedAt && now - p.disconnectedAt > graceMs) this.players.delete(id);
    }
  }
}

export class RoomManager {
  private rooms = new Map<string, GameRoom>();
  get(roomId: string): GameRoom {
    let room = this.rooms.get(roomId);
    if (!room) { room = new GameRoom(roomId); this.rooms.set(roomId, room); }
    return room;
  }
  values(): IterableIterator<GameRoom> { return this.rooms.values(); }
}
