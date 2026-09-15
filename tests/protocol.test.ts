import { describe, expect, it } from 'vitest';
import { parseClientMessage, PROTOCOL_VERSION } from '../packages/shared/src/index';

describe('protocol validation', () => {
  it('accepte un join valide', () => {
    expect(parseClientMessage(JSON.stringify({
      type: 'join', protocol: PROTOCOL_VERSION, roomId: 'ABC123', playerToken: 'token-123456',
    }))).not.toBeNull();
  });

  it('rejette JSON et room invalides', () => {
    expect(parseClientMessage('{')).toBeNull();
    expect(parseClientMessage(JSON.stringify({
      type: 'join', protocol: PROTOCOL_VERSION, roomId: '../bad', playerToken: 'token-123456',
    }))).toBeNull();
  });

  it('rejette des tirs mal types ou avec sequence negative', () => {
    expect(parseClientMessage(JSON.stringify({ type: 'shoot', sequence: 1, angle: '0', power: 0.5 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: 'shoot', sequence: -1, angle: 0, power: 0.5 }))).toBeNull();
  });
});
