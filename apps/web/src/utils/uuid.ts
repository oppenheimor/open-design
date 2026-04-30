export function createClientId(): string {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }

  return 'id-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 12);
}
