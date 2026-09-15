import { createGameServer } from './app';

const PORT = Number(process.env.PORT ?? 3000);
const { server } = createGameServer();
server.listen(PORT, '0.0.0.0', () => console.log(`Multiplayer Golf: http://localhost:${PORT}`));
