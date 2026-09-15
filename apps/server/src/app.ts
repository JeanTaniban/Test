import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { PROTOCOL_VERSION, TICK_RATE, parseClientMessage, type ServerMessage } from '../../../packages/shared/src/index';
import { RoomManager } from './room';

export type GameServerOptions = { serveClient?: boolean };

export function createGameServer(options: GameServerOptions = {}) {
  const serveClient = options.serveClient ?? true;
  const root = join(process.cwd(), 'apps/client/dist');
  const manager = new RoomManager();
  const mime: Record<string, string> = {
    '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.json': 'application/json',
  };

  const server = createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
      return;
    }
    if (!serveClient) {
      res.writeHead(404).end();
      return;
    }
    if (!existsSync(root)) {
      res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Client non compile. Lancez npm run build:client.');
      return;
    }
    const urlPath = decodeURIComponent((req.url ?? '/').split('?')[0] ?? '/');
    const candidate = normalize(join(root, urlPath));
    const file = candidate.startsWith(root) && existsSync(candidate) && statSync(candidate).isFile()
      ? candidate : join(root, 'index.html');
    res.writeHead(200, { 'content-type': mime[extname(file)] ?? 'application/octet-stream' });
    res.end(readFileSync(file));
  });

  const wss = new WebSocketServer({ server, path: '/ws' });
  type Session = { roomId?: string; playerId?: string };
  const sessions = new WeakMap<WebSocket, Session>();

  const send = (ws: WebSocket, msg: ServerMessage) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  };

  wss.on('connection', (ws) => {
    sessions.set(ws, {});
    ws.on('message', (raw) => {
      const msg = parseClientMessage(raw.toString());
      if (!msg) { send(ws, { type: 'error', code: 'BAD_MESSAGE', message: 'Message invalide.' }); return; }
      const session = sessions.get(ws)!;
      if (msg.type === 'join') {
        if (msg.protocol !== PROTOCOL_VERSION) {
          send(ws, { type: 'error', code: 'PROTOCOL', message: 'Version de protocole incompatible.' });
          return;
        }
        const room = manager.get(msg.roomId);
        const player = room.join(msg.playerToken, ws);
        session.roomId = room.id;
        session.playerId = player.state.id;
        send(ws, { type: 'welcome', playerId: player.state.id, roomId: room.id, state: room.snapshot().players });
        return;
      }
      if (msg.type === 'ping') {
        send(ws, { type: 'pong', clientTime: msg.clientTime, serverTime: Date.now() });
        return;
      }
      if (!session.roomId || !session.playerId) {
        send(ws, { type: 'error', code: 'NOT_JOINED', message: 'Join requis.' });
        return;
      }
      if (msg.type === 'shoot') manager.get(session.roomId).shoot(session.playerId, msg);
    });
    ws.on('close', () => {
      const session = sessions.get(ws);
      if (session?.roomId && session.playerId) manager.get(session.roomId).disconnect(session.playerId);
    });
  });

  const timer = setInterval(() => {
    for (const room of manager.values()) {
      room.step();
      room.cleanupDisconnected();
      if (!room.shouldSnapshot()) continue;
      const payload = JSON.stringify(room.snapshot());
      for (const player of room.players.values()) {
        if (player.socket?.readyState === WebSocket.OPEN) player.socket.send(payload);
      }
    }
  }, 1000 / TICK_RATE);

  async function close(): Promise<void> {
    clearInterval(timer);
    for (const client of wss.clients) client.terminate();
    await new Promise<void>((resolve) => wss.close(() => resolve()));
    if (server.listening) await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }

  return { server, wss, manager, close };
}
