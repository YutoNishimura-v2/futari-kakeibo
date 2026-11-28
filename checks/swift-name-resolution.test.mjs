import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

// Swift cannot be compiled on Windows, so these checks catch two name-resolution
// errors the iOS build reported (round 5): a call to a helper that is never
// declared, and a local constant that shadows a method called earlier in the
// same function ("circular reference").

const root = fileURLToPath(new URL('../', import.meta.url));

function swiftFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return swiftFiles(full);
    return entry.name.endsWith('.swift') ? [full] : [];
  });
}

/** Source with comments and string literals blanked out, keeping offsets. */
function codeOnly(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length))
    .replace(/"(?:\\.|[^"\\\n])*"/g, (m) => `"${' '.repeat(m.length - 2)}"`);
}

/** Bodies of every `func` (start/end offsets of the text between its braces). */
function functionBodies(code) {
  const bodies = [];
  for (const match of code.matchAll(/\bfunc\s+\w+/g)) {
    const open = code.indexOf('{', match.index);
    if (open < 0) continue;
    let depth = 0;
    for (let i = open; i < code.length; i += 1) {
      if (code[i] === '{') depth += 1;
      else if (code[i] === '}' && (depth -= 1) === 0) {
        bodies.push({ name: match[0], start: open + 1, end: i });
        break;
      }
    }
  }
  return bodies;
}

const sources = [...swiftFiles(path.join(root, 'Sources')), ...swiftFiles(path.join(root, 'Tests'))]
  .map((file) => ({ file: path.relative(root, file), code: codeOnly(readFileSync(file, 'utf8')) }));
const declaredFunctions = new Set(sources.flatMap(({ code }) => [...code.matchAll(/\bfunc\s+(\w+)/g)].map((m) => m[1])));

test('every helper called with try is declared in the app sources', () => {
  const missing = [];
  for (const { file, code } of sources) {
    for (const match of code.matchAll(/\btry[?!]?\s+([a-z]\w*)\s*\(/g)) {
      const name = match[1];
      const closureParameter = new RegExp(`\\b${name}\\s*:\\s*(?:@\\w+\\s+)*\\(`).test(code);
      if (!declaredFunctions.has(name) && !closureParameter) missing.push(`${file}: ${name}`);
    }
  }
  assert.deepEqual(missing, []);
});

test('no local constant shadows a method that the same function calls without self', () => {
  const clashes = [];
  for (const { file, code } of sources) {
    const methods = new Set([...code.matchAll(/\bfunc\s+(\w+)/g)].map((m) => m[1]));
    for (const body of functionBodies(code)) {
      const text = code.slice(body.start, body.end);
      // `if let` / `while let` / `case let` bind only inside their own block, so they are skipped.
      for (const local of text.matchAll(/(?<!\b(?:if|while|case)\s+)\b(?:let|var)\s+(\w+)\s*(?::[^=\n]+)?=/g)) {
        const name = local[1];
        if (!methods.has(name)) continue;
        const unqualified = new RegExp(`(?<![.\\w])${name}\\s*\\(`, 'g');
        if (unqualified.test(text)) clashes.push(`${file} ${body.name}: ${name}`);
      }
    }
  }
  assert.deepEqual(clashes, []);
});
