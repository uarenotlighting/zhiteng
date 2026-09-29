/** Paths that stay plaintext GET (health / docs), outside the unified POST envelope. */
export function isPublicPlaintextGet(pathname: string, method = 'GET') {
  if (method.toUpperCase() !== 'GET') return false;
  const path = pathname.split('?')[0];
  return (
    path === '/v1/health' ||
    path.startsWith('/v1/health/') ||
    path === '/docs' ||
    path.startsWith('/docs/') ||
    path === '/docs-json' ||
    path === '/'
  );
}
