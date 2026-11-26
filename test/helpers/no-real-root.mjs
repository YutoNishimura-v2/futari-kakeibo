import { relative } from 'node:path';
import { fileURLToPath } from 'node:url';

// Run local checks from this checkout, with only in-memory test fixtures.
const checkout = fileURLToPath(new URL('../../', import.meta.url));
if (relative(checkout, process.cwd()) !== '') {
  throw new Error('Start the ledger tests from their repository root.');
}
