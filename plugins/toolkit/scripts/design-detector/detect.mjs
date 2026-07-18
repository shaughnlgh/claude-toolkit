// Toolkit CLI entry point (MIT licensed, this repo's root LICENSE).
// Thin standalone wrapper around the vendored Impeccable detection engine —
// see NOTICE and README.md in this directory for attribution.
//
// Usage: node detect.mjs <file> [file ...]

import fs from 'node:fs';
import path from 'node:path';

import { detectText } from './vendor/engines/regex/detect-text.mjs';
import { detectHtml } from './vendor/engines/static-html/detect-html.mjs';

const HTML_EXTS = new Set(['.html', '.htm']);

async function detectFile(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (HTML_EXTS.has(ext)) {
    return detectHtml(filePath, {});
  }
  const content = fs.readFileSync(filePath, 'utf-8');
  return detectText(content, filePath, {});
}

async function main(files) {
  if (files.length === 0) {
    console.error('Usage: node detect.mjs <file> [file ...]');
    process.exit(0);
    return;
  }

  let total = 0;
  for (const filePath of files) {
    console.log(filePath);
    let findings;
    try {
      findings = await detectFile(filePath);
    } catch (err) {
      console.log(`  (error: ${err.message})`);
      console.log('');
      continue;
    }
    if (findings.length === 0) {
      console.log('  (no findings)');
    }
    for (const f of findings) {
      const location = f.line ? ` (line ${f.line})` : '';
      console.log(`  [${f.antipattern}] ${f.name}${location}: ${f.description}`);
    }
    total += findings.length;
    console.log('');
  }

  console.log(`Total findings: ${total}`);
  process.exit(0);
}

const args = process.argv.slice(2);
main(args);
