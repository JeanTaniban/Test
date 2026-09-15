import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { PROTOCOL_VERSION, TICK_RATE, parseClientMessage, type ServerMessage } from '../../../packages/shared/src/index';
import { RoomManager } from './room';

export type GameServerOptions = { serveClient?: boolean };

const diagnosticsEnabled = process.env.SERVER_DIAGNOSTICS === '1';

function diagnostic(message: string): void {
  if (!diagnosticsEnabled) return;
  console.log(`[${new Date().toISOString()}] [net] ${message}`);
}

export function createGameServer(options: GameServerOptions = {}) {
  const serveClient = options.serveClient ?? true;
  const root = join(process.cwd(), 'apps/client/dist');
  const manager = new RoomManager();
  const mime: Record<string, string> = {
    '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.json': 'application/json',
  };

  const server = createServer((req, res) => {
    const started = Date.now();
    const requestId = Math.random().toString(36).slice(2, 8);
    const remote = `${req.socket.remoteAddress ?? '?'}:${req.socket.remotePort ?? '?'}`;
    diagnostic(`http begin id=${requestId} method=${req.method ?? '?'} url=${req.url ?? '?'} host=${req.headers.host ?? '?'} remote=${remote} ua=${JSON.stringify(req.headers['user-agent'] ?? '')}`);
    res.on('finish', () => {
      diagnostic(`http end id=${requestId} status=${res.statusCode} durationMs=${Date.now() - started} url=${req.url ?? '?'}`);
    });
    res.on('close', () => {
      if (!res.writableEnded) diagnostic(`http aborted id=${requestId} durationMs=${Date.now() - started} url=${req.url ?? '?'}`);
    });

    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify({ ok: true, pid: process.pid, uptime: Math.round(process.uptime()) }));
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
    diagnostic(`http static id=${requestId} file=${file}`);
    res.writeHead(200, { 'content-type': mime[extname(file)] ?? 'application/octet-stream' });
    res.end(readFileSync(file));
  });

  server.on('upgrade', (req) => {
    diagnostic(`ws upgrade method=${req.method ?? '?'} url=${req.url ?? '?'} host=${req.headers.host ?? '?'} remote=${req.socket.remoteAddress ?? '?'} ua=${JSON.stringify(req.headers['user-agent'] ?? '')}`);
  });
  server.on('clientError', (error) => {
    diagnostic(`http clientError error=${JSON.stringify(error.message)}`);
  });
  server.on('close', () => diagnostic('http server close event'));

  const wss = new WebSocketServer({ server, path: '/ws' });
  type Session = { roomId?: string; playerId?: string };
  const sessions = new WeakMap<WebSocket, Session>();

  const send = (ws: WebSocket, msg: ServerMessage) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  };

  wss.on('connection', (ws, req) => {
    diagnostic(`ws connected url=${req.url ?? '?'} host=${req.headers.host ?? '?'} clients=${wss.clients.size}`);
    sessions.set(ws, {});
    ws.on('message', (raw) => {
      const msg = parseClientMessage(raw.toString());
      if (!msg) {
        diagnostic(`ws BAD_MESSAGE bytes=${raw.toString().length}`);
        send(ws, { type: 'error', code: 'BAD_MESSAGE', message: 'Message invalide.' });
        return;
      }
      const session = sessions.get(ws)!;
      if (msg.type === 'join') {
        diagnostic(`ws join room=${msg.roomId} protocol=${msg.protocol}`);
        if (msg.protocol !== PROTOCOL_VERSION) {
          send(ws, { type: 'error', code: 'PROTOCOL', message: 'Version de protocole incompatible.' });
          return;
        }
        const room = manager.get(msg.roomId);
        const player = room.join(msg.playerToken, ws);
        session.roomId = room.id;
        session.playerId = player.state.id;
        diagnostic(`ws welcomed room=${room.id} player=${player.state.id} players=${room.players.size}`);
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
      if (msg.type === 'shoot') {
        diagnostic(`ws shoot room=${session.roomId} player=${session.playerId} seq=${msg.sequence} power=${msg.power}`);
        manager.get(session.roomId).shoot(session.playerId, msg);
      }
    });
    ws.on('error', (error) => diagnostic(`ws error message=${JSON.stringify(error.message)}`));
    ws.on('close', (code, reason) => {
      const session = sessions.get(ws);
      diagnostic(`ws close code=${code} reason=${JSON.stringify(reason.toString())} room=${session?.roomId ?? '?'} player=${session?.playerId ?? '?'} clients=${wss.clients.size}`);
      if (session?.roomId && session.playerId) manager.get(session.roomId).disconnect(session.playerId);
    });
  });
  wss.on('error', (error) => diagnostic(`wss error message=${JSON.stringify(error.message)}`));
  wss.on('close', () => diagnostic('wss close event'));

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
