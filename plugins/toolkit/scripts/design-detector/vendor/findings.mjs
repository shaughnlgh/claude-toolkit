// Vendored from pbakaus/impeccable (https://github.com/pbakaus/impeccable) @ 8967edc, Apache-2.0. Relocated for standalone use; otherwise unmodified.

import { getAntipattern } from './registry/antipatterns.mjs';

function getAP(id) {
  return getAntipattern(id);
}

function finding(id, filePath, snippet, line = 0) {
  const ap = getAP(id);
  return { antipattern: id, name: ap.name, description: ap.description, severity: ap.severity || 'warning', file: filePath, line, snippet };
}

export { getAP, finding };
