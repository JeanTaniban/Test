import type { AddressInfo } from 'node:net';
import { afterEach, describe, expect, it } from 'vitest';
import { WebSocket, type RawData } from 'ws';
import { PROTOCOL_VERSION, type ServerMessage } from '../packages/shared/src/index';
import { createGameServer } from '../apps/server/src/app';

function openSocket(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

function nextMessage<T extends ServerMessage['type']>(ws: WebSocket, type: T, timeoutMs = 2000): Promise<Extract<ServerMessage, { type: T }>> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { cleanup(); reject(new Error(`Timeout waiting for ${type}`)); }, timeoutMs);
    const onMessage = (data: RawData) => {
      const msg = JSON.parse(data.toString()) as ServerMessage;
      if (msg.type !== type) return;
      cleanup();
      resolve(msg as Extract<ServerMessage, { type: T }>);
    };
    const cleanup = () => { clearTimeout(timer); ws.off('message', onMessage); };
    ws.on('message', onMessage);
  });
}

describe('websocket integration', () => {
  const resources: Array<() => Promise<void>> = [];
  afterEach(async () => {
    while (resources.length) await resources.pop()!();
  });

  it('synchronise deux joueurs, un tir et une reconnexion', async () => {
    const game = createGameServer({ serveClient: false });
    await new Promise<void>((resolve) => game.server.listen(0, '127.0.0.1', () => resolve()));
    resources.push(() => game.close());
    const port = (game.server.address() as AddressInfo).port;
    const url = `ws://127.0.0.1:${port}/ws`;

    const a = await openSocket(url);
    const welcomeAPromise = nextMessage(a, 'welcome');
    a.send(JSON.stringify({ type: 'join', protocol: PROTOCOL_VERSION, roomId: 'ROOM1', playerToken: 'token-player-a' }));
    const welcomeA = await welcomeAPromise;

    const b = await openSocket(url);
    const welcomeBPromise = nextMessage(b, 'welcome');
    b.send(JSON.stringify({ type: 'join', protocol: PROTOCOL_VERSION, roomId: 'ROOM1', playerToken: 'token-player-b' }));
    const welcomeB = await welcomeBPromise;
    expect(welcomeB.state).toHaveLength(2);

    const snapshotA = nextMessage(a, 'snapshot');
    const snapshotB = nextMessage(b, 'snapshot');
    a.send(JSON.stringify({ type: 'shoot', sequence: 1, angle: 0, power: 0.5 }));
    const [stateA, stateB] = await Promise.all([snapshotA, snapshotB]);
    const playerA1 = stateA.players.find((player) => player.id === welcomeA.playerId)!;
    const playerA2 = stateB.players.find((player) => player.id === welcomeA.playerId)!;
    expect(playerA1.shots).toBe(1);
    expect(playerA2.shots).toBe(1);
    expect(playerA1.x).toBeCloseTo(playerA2.x, 6);

    a.close();
    await new Promise<void>((resolve) => a.once('close', () => resolve()));
    const reconnected = await openSocket(url);
    const reconnectPromise = nextMessage(reconnected, 'welcome');
    reconnected.send(JSON.stringify({ type: 'join', protocol: PROTOCOL_VERSION, roomId: 'ROOM1', playerToken: 'token-player-a' }));
    const reconnectWelcome = await reconnectPromise;
    expect(reconnectWelcome.playerId).toBe(welcomeA.playerId);
    expect(reconnectWelcome.state).toHaveLength(2);

    reconnected.close();
    b.close();
  });
});
