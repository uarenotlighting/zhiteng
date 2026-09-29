/**
 * Production transport encryption cannot be disabled by configuration.
 * Development and test environments default to plaintext for easier debugging.
 */
export function isTransportEncryptionEnabled() {
  if (process.env.NODE_ENV === 'production') return true;
  return process.env.TRANSPORT_ENCRYPTION === 'true';
}
