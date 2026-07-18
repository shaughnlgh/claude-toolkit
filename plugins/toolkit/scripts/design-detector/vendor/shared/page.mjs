// Vendored from pbakaus/impeccable (https://github.com/pbakaus/impeccable) @ 8967edc, Apache-2.0. Relocated for standalone use; otherwise unmodified.

/** Check if content looks like a full page (not a component/partial) */
function isFullPage(content) {
  const stripped = content.replace(/<!--[\s\S]*?-->/g, '');
  return /<!doctype\s|<html[\s>]|<head[\s>]/i.test(stripped);
}

export { isFullPage };
