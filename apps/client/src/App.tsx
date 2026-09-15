import { useEffect, useMemo, useRef, useState } from 'react';
import { BALL_RADIUS, FIELD, HOLE, PROTOCOL_VERSION, type PlayerState, type ServerMessage } from '../../../packages/shared/src/index';

type Frame = { at: number; players: PlayerState[] };

function roomFromPath(): string {
  const match = location.pathname.match(/^\/game\/([A-Za-z0-9_-]{1,32})/);
  if (match) return match[1]!;
  const id = crypto.randomUUID().replace(/-/g, '').slice(0, 6).toUpperCase();
  history.replaceState(null, '', `/game/${id}`);
  return id;
}

function playerToken(): string {
  const key = 'multiplayer-golf-token';
  let value = localStorage.getItem(key);
  if (!value) {
    value = crypto.randomUUID();
    localStorage.setItem(key, value);
  }
  return value;
}

export function App() {
  const roomId = useMemo(roomFromPath, []);
  const [status, setStatus] = useState('connexion…');
  const [me, setMe] = useState<string>();
  const [players, setPlayers] = useState<PlayerState[]>([]);
  const wsRef = useRef<WebSocket | null>(null);
  const frames = useRef<Frame[]>([]);
  const sequence = useRef(0);
  const canvas = useRef<HTMLCanvasElement>(null);
  const drag = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    let retry: number | undefined;
    let stopped = false;

    const connect = () => {
      const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const ws = new WebSocket(`${protocol}//${location.host}/ws`);
      wsRef.current = ws;

      ws.onopen = () => {
        setStatus('connecté');
        ws.send(JSON.stringify({
          type: 'join', protocol: PROTOCOL_VERSION, roomId, playerToken: playerToken(),
        }));
      };

      ws.onmessage = (event) => {
        const msg = JSON.parse(event.data) as ServerMessage;
        if (msg.type === 'welcome') {
          setMe(msg.playerId);
          setPlayers(msg.state);
        }
        if (msg.type === 'snapshot') {
          frames.current.push({ at: performance.now(), players: msg.players });
          if (frames.current.length > 3) frames.current.shift();
          setPlayers(msg.players);
        }
        if (msg.type === 'error') setStatus(`erreur: ${msg.message}`);
      };

      ws.onclose = () => {
        setStatus('reconnexion…');
        if (!stopped) retry = window.setTimeout(connect, 1000);
      };
    };

    connect();
    return () => {
      stopped = true;
      if (retry) clearTimeout(retry);
      wsRef.current?.close();
    };
  }, [roomId]);

  useEffect(() => {
    const element = canvas.current!;
    const ctx = element.getContext('2d')!;
    let animationFrame = 0;

    const render = () => {
      const dpr = devicePixelRatio || 1;
      if (element.width !== FIELD.width * dpr || element.height !== FIELD.height * dpr) {
        element.width = FIELD.width * dpr;
        element.height = FIELD.height * dpr;
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, FIELD.width, FIELD.height);
      ctx.fillStyle = '#174f2a';
      ctx.fillRect(0, 0, FIELD.width, FIELD.height);
      ctx.strokeStyle = '#d8f1df';
      ctx.lineWidth = 4;
      ctx.strokeRect(2, 2, FIELD.width - 4, FIELD.height - 4);
      ctx.fillStyle = '#101418';
      ctx.beginPath();
      ctx.arc(HOLE.x, HOLE.y, HOLE.radius, 0, Math.PI * 2);
      ctx.fill();

      const now = performance.now();
      const previous = frames.current.at(-2);
      const latest = frames.current.at(-1);
      const alpha = previous && latest
        ? Math.min(1, Math.max(0, (now - latest.at + 100) / Math.max(1, latest.at - previous.at)))
        : 1;

      const displayed = players.map((player) => {
        const old = previous?.players.find((candidate) => candidate.id === player.id);
        if (!old || player.id === me) return player;
        return {
          ...player,
          x: old.x + (player.x - old.x) * alpha,
          y: old.y + (player.y - old.y) * alpha,
        };
      });

      for (const player of displayed) {
        if (player.finished) continue;
        ctx.fillStyle = player.id === me ? '#ffd54a' : '#e7eef7';
        ctx.beginPath();
        ctx.arc(player.x, player.y, BALL_RADIUS, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#0008';
        ctx.lineWidth = 2;
        ctx.stroke();
      }

      animationFrame = requestAnimationFrame(render);
    };

    render();
    return () => cancelAnimationFrame(animationFrame);
  }, [players, me]);

  const toGamePoint = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left) * FIELD.width / rect.width,
      y: (event.clientY - rect.top) * FIELD.height / rect.height,
    };
  };

  const pointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const point = toGamePoint(event);
    const mine = players.find((player) => player.id === me);
    if (!mine || mine.finished || Math.hypot(point.x - mine.x, point.y - mine.y) > BALL_RADIUS * 2) return;
    drag.current = point;
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const pointerUp = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const start = drag.current;
    drag.current = null;
    if (!start || !me) return;
    const end = toGamePoint(event);
    const dx = start.x - end.x;
    const dy = start.y - end.y;
    const distance = Math.hypot(dx, dy);
    if (distance < 5) return;
    wsRef.current?.send(JSON.stringify({
      type: 'shoot',
      sequence: sequence.current++,
      angle: Math.atan2(dy, dx),
      power: Math.min(1, distance / 180),
    }));
  };

  const mine = players.find((player) => player.id === me);
  const sorted = [...players].sort((a, b) => a.shots - b.shots);

  return <main>
    <header>
      <div><h1>Multiplayer Golf</h1><span>{status} · room {roomId}</span></div>
      <button onClick={() => navigator.clipboard.writeText(location.href)}>Copier le lien</button>
    </header>
    <section className="game">
      <canvas ref={canvas} onPointerDown={pointerDown} onPointerUp={pointerUp}/>
    </section>
    <aside>
      <strong>Coups : {mine?.shots ?? 0}</strong>
      <span>{mine?.finished ? 'Terminé !' : 'Clique-glisse depuis votre balle pour tirer.'}</span>
    </aside>
    <ol>{sorted.map((player) => <li key={player.id}>
      {player.id === me ? 'Vous' : `Joueur ${player.id.slice(0, 4)}`} — {player.shots} coup(s)
      {player.finished ? ' ✓' : ''}{!player.connected ? ' (déconnecté)' : ''}
    </li>)}</ol>
  </main>;
}
