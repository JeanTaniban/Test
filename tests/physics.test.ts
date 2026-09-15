import { describe, expect, it } from 'vitest';
import { BALL_RADIUS, FIELD, HOLE, type PlayerState } from '../packages/shared/src/index';
import { integratePlayer, isInHole, resolveBallCollision, resolveWalls } from '../apps/server/src/physics';

const player = (x = 100, y = 100, vx = 0, vy = 0): PlayerState => ({
  id: crypto.randomUUID(), x, y, vx, vy, shots: 0, finished: false, connected: true,
});

describe('physics', () => {
  it('integre la position et amortit la vitesse', () => {
    const value = player(100, 100, 60, 0);
    integratePlayer(value, 1 / 60);
    expect(value.x).toBeGreaterThan(100);
    expect(value.vx).toBeLessThan(60);
  });

  it('rebondit sur une paroi', () => {
    const value = player(2, 100, -50, 0);
    resolveWalls(value);
    expect(value.x).toBe(BALL_RADIUS);
    expect(value.vx).toBeGreaterThan(0);
  });

  it('resout une collision balle-balle et la penetration', () => {
    const a = player(100, 100, 50, 0);
    const b = player(120, 100, -20, 0);
    resolveBallCollision(a, b);
    expect(a.vx).toBeLessThan(50);
    expect(b.vx).toBeGreaterThan(-20);
    expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeCloseTo(BALL_RADIUS * 2, 5);
  });

  it('accepte le trou seulement a faible vitesse', () => {
    const value = player(HOLE.x, HOLE.y, 10, 0);
    expect(isInHole(value)).toBe(true);
    value.vx = 500;
    expect(isInHole(value)).toBe(false);
  });

  it('maintient une balle dans les limites du terrain', () => {
    const value = player(FIELD.width + 30, FIELD.height + 30, 10, 10);
    resolveWalls(value);
    expect(value.x).toBeLessThanOrEqual(FIELD.width - BALL_RADIUS);
    expect(value.y).toBeLessThanOrEqual(FIELD.height - BALL_RADIUS);
  });
});
