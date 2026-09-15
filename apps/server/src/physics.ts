import {
  BALL_RADIUS, BALL_RESTITUTION, DT, FIELD, HOLE, LINEAR_DAMPING,
  STOP_SPEED, WALL_RESTITUTION, type PlayerState,
} from '../../../packages/shared/src/index';

export function integratePlayer(p: PlayerState, dt = DT): void {
  if (p.finished) return;
  p.x += p.vx * dt;
  p.y += p.vy * dt;
  const damping = Math.exp(-LINEAR_DAMPING * dt);
  p.vx *= damping;
  p.vy *= damping;
  if (Math.hypot(p.vx, p.vy) < STOP_SPEED) p.vx = p.vy = 0;
}

export function resolveWalls(p: PlayerState): void {
  if (p.finished) return;
  if (p.x < BALL_RADIUS) { p.x = BALL_RADIUS; p.vx = Math.abs(p.vx) * WALL_RESTITUTION; }
  if (p.x > FIELD.width - BALL_RADIUS) { p.x = FIELD.width - BALL_RADIUS; p.vx = -Math.abs(p.vx) * WALL_RESTITUTION; }
  if (p.y < BALL_RADIUS) { p.y = BALL_RADIUS; p.vy = Math.abs(p.vy) * WALL_RESTITUTION; }
  if (p.y > FIELD.height - BALL_RADIUS) { p.y = FIELD.height - BALL_RADIUS; p.vy = -Math.abs(p.vy) * WALL_RESTITUTION; }
}

export function resolveBallCollision(a: PlayerState, b: PlayerState): void {
  if (a.finished || b.finished) return;
  let dx = b.x - a.x;
  let dy = b.y - a.y;
  let dist = Math.hypot(dx, dy);
  const minDist = BALL_RADIUS * 2;
  if (dist >= minDist) return;
  if (dist === 0) { dx = 1; dy = 0; dist = 1; }
  const nx = dx / dist;
  const ny = dy / dist;
  const penetration = minDist - dist;
  a.x -= nx * penetration * 0.5;
  a.y -= ny * penetration * 0.5;
  b.x += nx * penetration * 0.5;
  b.y += ny * penetration * 0.5;
  const rel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
  if (rel >= 0) return;
  const impulse = -(1 + BALL_RESTITUTION) * rel / 2;
  a.vx -= impulse * nx;
  a.vy -= impulse * ny;
  b.vx += impulse * nx;
  b.vy += impulse * ny;
}

export function isInHole(p: PlayerState): boolean {
  return Math.hypot(p.x - HOLE.x, p.y - HOLE.y) <= HOLE.radius - BALL_RADIUS * 0.25
    && Math.hypot(p.vx, p.vy) <= HOLE.maxEntrySpeed;
}
