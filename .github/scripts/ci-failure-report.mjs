// Build the public failure report (index.md and .txt step logs) for the ci-shots branch.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Steps whose output is saved as tmp/ci-logs/<id>.log by .github/workflows/screenshots.yml.
export const LOGGED_STEPS = [
  { id: 'prepare', title: 'Prepare project and simulator' },
  { id: 'capture', title: 'Build and capture' },
  { id: 'export', title: 'Export screenshot attachments' },
  { id: 'publish', title: 'Publish the screenshot branch' },
];

const TAIL_LINES = 150;
const MAX_ERROR_LINES = 200;
const MAX_LINE_LENGTH = 400;
const ERROR_PATTERNS = [
  /\berror:/i,
  /\bfatal:/i,
  /\*\* BUILD FAILED \*\*/,
  /Testing failed/,
  /xcodegen.*\b(error|fail)/i,
  /Spec validation error|Parsing spec failed|Generation failed/,
  /command not found/,
];

/** Drop mask commands and Authorization headers, and redact token strings before publishing logs. */
export function sanitizeLog(text) {
  const masked = [];
  for (const match of text.matchAll(/::add-mask::([^\r\n]+)/gi)) {
    const secret = match[1].trim();
    if (secret.length >= 4) masked.push(secret);
  }
  let out = text
    .replace(/^(?:::add-mask::|[^\r\n]*Authorization:)[^\r\n]*(?:\r\n?|\n|$)/gim, '')
    .replace(/(::add-mask::)[^\r\n]*/gi, '$1[REDACTED]')
    .replace(/(x-access-token:)[^\s'"@]+/gi, '$1[REDACTED]')
    .replace(/\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github[_]pat_[A-Za-z0-9_]{20,})\b/g, '[REDACTED]');
  for (const secret of masked) {
    out = out.replaceAll(secret, '[REDACTED]');
  }
  return out;
}

function clip(line) {
  return line.length > MAX_LINE_LENGTH ? `${line.slice(0, MAX_LINE_LENGTH)}…` : line;
}

function splitLines(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  if (lines.at(-1) === '') lines.pop();
  return lines;
}

/** Unique lines of a log that look like errors, in order, capped. */
export function findErrorLines(text) {
  const found = [];
  const seen = new Set();
  for (const line of splitLines(text)) {
    if (!ERROR_PATTERNS.some((pattern) => pattern.test(line))) continue;
    const shown = clip(line.trim());
    if (seen.has(shown)) continue;
    seen.add(shown);
    found.push(shown);
  }
  return found;
}

/** First step whose outcome is failure, from the `toJSON(steps)` context. */
export function findFailedStep(steps) {
  const id = Object.keys(steps).find((key) => steps[key]?.outcome === 'failure');
  if (id === undefined) return { id: undefined, title: '不明' };
  const known = LOGGED_STEPS.find((step) => step.id === id);
  return { id, title: known?.title ?? id };
}

// A fence longer than any backtick or tilde run in the log cannot be closed by the log itself.
function fenceFor(lines) {
  const longest = Math.max(0, ...lines.map((line) => (line.match(/^\s*([`~]{3,})/)?.[1].length ?? 0)));
  return '~'.repeat(Math.max(4, longest + 1));
}

export function buildReport({ sha, runUrl, steps, logs }) {
  const cleanLogs = Object.fromEntries(
    Object.entries(logs).map(([id, text]) => [id, text === undefined ? undefined : sanitizeLog(text)]),
  );
  const failed = findFailedStep(steps);
  const out = [
    `失敗 ${sha}`,
    '',
    '# ふたりの家計簿: 画面撮影の失敗',
    '',
    `- コミット: ${sha}`,
    `- 実行: ${runUrl}`,
    `- 失敗した手順: ${failed.title}${failed.id ? ` (${failed.id})` : ''}`,
    '',
    '## エラー行',
    '',
  ];
  const errorBlocks = [];
  for (const step of LOGGED_STEPS) {
    const text = cleanLogs[step.id];
    if (text === undefined) continue;
    errorBlocks.push({ step, lines: findErrorLines(text) });
  }
  const total = errorBlocks.reduce((sum, block) => sum + block.lines.length, 0);
  if (total === 0) out.push('該当する行はありません。下のログを見てください。', '');
  let budget = MAX_ERROR_LINES;
  for (const { step, lines } of errorBlocks) {
    if (lines.length === 0) continue;
    const shown = lines.slice(0, Math.max(0, budget));
    budget -= shown.length;
    const fence = fenceFor(shown);
    out.push(`### ${step.title}`, '', `${fence}text`, ...shown, fence, '');
    if (shown.length < lines.length) out.push(`（ほか ${lines.length - shown.length} 行は ${step.id}.txt を見てください）`, '');
  }
  out.push(`## ログの末尾${TAIL_LINES}行`, '');
  for (const step of LOGGED_STEPS) {
    out.push(`### ${step.title}`, '');
    const text = cleanLogs[step.id];
    if (text === undefined) {
      out.push('ログなし（この手順は実行されませんでした）', '');
      continue;
    }
    const tail = splitLines(text).slice(-TAIL_LINES).map(clip);
    const fence = fenceFor(tail);
    out.push(`全文: [${step.id}.txt](${step.id}.txt)`, '', `${fence}text`, ...tail, fence, '');
  }
  return `${out.join('\n')}\n`;
}

/** Read tmp/ci-logs, write the sanitized report and .txt copies under `outDir`. */
export function writeReport({ logDir, outDir, sha, runUrl, steps }) {
  const logs = {};
  mkdirSync(outDir, { recursive: true });
  for (const step of LOGGED_STEPS) {
    const file = join(logDir, `${step.id}.log`);
    if (!existsSync(file)) continue;
    const sanitized = sanitizeLog(readFileSync(file, 'utf8'));
    logs[step.id] = sanitized;
    writeFileSync(join(outDir, `${step.id}.txt`), sanitized, 'utf8');
  }
  writeFileSync(join(outDir, 'index.md'), buildReport({ sha, runUrl, steps, logs }), 'utf8');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const { GITHUB_SHA, GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID, STEPS_JSON } = process.env;
  writeReport({
    logDir: 'tmp/ci-logs',
    outDir: process.argv[2] || 'tmp/ci-failure',
    sha: GITHUB_SHA,
    runUrl: `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}`,
    steps: JSON.parse(STEPS_JSON ?? '{}'),
  });
}
