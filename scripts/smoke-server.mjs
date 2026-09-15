import { spawn } from 'node:child_process';

const port = 31337;
const child = spawn(
  process.execPath,
  ['dist/server/apps/server/src/index.js'],
  {
    cwd: process.cwd(),
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  },
);

let output = '';
child.stdout.on('data', (chunk) => { output += chunk.toString(); });
child.stderr.on('data', (chunk) => { output += chunk.toString(); });

try {
  let ok = false;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (child.exitCode !== null) break;
    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`);
      if (response.ok) {
        const body = await response.json();
        if (body?.ok === true) {
          ok = true;
          break;
        }
      }
    } catch {
      // Server is not ready yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  if (!ok) {
    console.error('Compiled server did not pass /health smoke test.');
    console.error(output);
    process.exitCode = 1;
  } else {
    console.log('Compiled server /health smoke test: OK');
  }
} finally {
  if (child.exitCode === null) child.kill('SIGTERM');
}
