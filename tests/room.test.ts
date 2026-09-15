import { describe, expect, it } from 'vitest';
import { GameRoom } from '../apps/server/src/room';

describe('room rules', () => {
  it('compte un tir valide une seule fois', () => {
    const room = new GameRoom('A');
    const player = room.join('token-123456');
    expect(room.shoot(player.state.id, { type: 'shoot', sequence: 1, angle: 0, power: 0.5 })).toBe(true);
    expect(player.state.shots).toBe(1);
    expect(room.shoot(player.state.id, { type: 'shoot', sequence: 1, angle: 0, power: 0.5 })).toBe(false);
    expect(player.state.shots).toBe(1);
  });

  it('rejette une puissance invalide sans compter de coup', () => {
    const room = new GameRoom('A');
    const player = room.join('token-123456');
    expect(room.shoot(player.state.id, { type: 'shoot', sequence: 1, angle: 0, power: 2 })).toBe(false);
    expect(player.state.shots).toBe(0);
  });

  it('interdit le tir une fois le joueur termine', () => {
    const room = new GameRoom('A');
    const player = room.join('token-123456');
    player.state.finished = true;
    expect(room.shoot(player.state.id, { type: 'shoot', sequence: 1, angle: 0, power: 0.5 })).toBe(false);
    expect(player.state.shots).toBe(0);
  });

  it('reconnecte le meme token a la meme balle', () => {
    const room = new GameRoom('A');
    const first = room.join('token-123456');
    room.disconnect(first.state.id);
    const second = room.join('token-123456');
    expect(second.state.id).toBe(first.state.id);
    expect(room.players.size).toBe(1);
    expect(second.state.connected).toBe(true);
  });

  it('produit des snapshots a 20 Hz pour une simulation a 60 Hz', () => {
    const room = new GameRoom('A');
    room.join('token-123456');
    room.step();
    expect(room.shouldSnapshot()).toBe(false);
    room.step();
    expect(room.shouldSnapshot()).toBe(false);
    room.step();
    expect(room.shouldSnapshot()).toBe(true);
  });
});
