import { createGameServer } from './app';

const PORT = Number(process.env.PORT ?? 3000);
const diagnosticsEnabled = process.env.SERVER_DIAGNOSTICS === '1';
const startedAt = Date.now();
const game = createGameServer();
const { server } = game;

function stamp(message: string): string {
  return `[${new Date().toISOString()}] ${message}`;
}

function logLifecycle(message: string): void {
  console.log(stamp(`[lifecycle] ${message}`));
}

function logError(message: string, error: unknown): void {
  const detail = error instanceof Error ? (error.stack ?? error.message) : String(error);
  console.error(stamp(`[fatal] ${message}: ${detail}`));
}

let shuttingDown = false;
async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  logLifecycle(`received ${signal}; closing server pid=${process.pid}`);
  try {
    await game.close();
    logLifecycle(`graceful shutdown complete after ${Math.round((Date.now() - startedAt) / 1000)}s`);
    process.exit(0);
  } catch (error) {
    logError('shutdown failed', error);
    process.exit(1);
  }
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('uncaughtException', (error) => {
  logError('uncaughtException', error);
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  logError('unhandledRejection', reason);
  process.exit(1);
});
process.on('exit', (code) => {
  console.log(stamp(`[lifecycle] process exit code=${code} pid=${process.pid}`));
});

server.on('error', (error) => {
  logError('HTTP server error', error);
});

server.listen(PORT, '0.0.0.0', () => {
  const address = server.address();
  logLifecycle(
    `listening pid=${process.pid} node=${process.version} platform=${process.platform}/${process.arch} cwd=${process.cwd()} address=${JSON.stringify(address)}`,
  );
  console.log(`Multiplayer Golf: http://localhost:${PORT}`);
});

if (diagnosticsEnabled) {
  const heartbeat = setInterval(() => {
    const memory = process.memoryUsage();
    console.log(stamp(
      `[heartbeat] pid=${process.pid} uptime=${Math.round(process.uptime())}s rss=${memory.rss} heapUsed=${memory.heapUsed} external=${memory.external}`,
    ));
  }, 30_000);
  heartbeat.unref();
}
