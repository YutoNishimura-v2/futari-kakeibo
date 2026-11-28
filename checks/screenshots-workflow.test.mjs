import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { LOGGED_STEPS, buildReport, findErrorLines, findFailedStep, writeReport } from '../.github/scripts/ci-failure-report.mjs';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const workflow = read('.github/workflows/screenshots.yml');

// Split the steps list into blocks keyed by their `- name:` / `- uses:` line (no YAML parser in the repo).
const steps = workflow
  .split(/^ {6}- (?=name:|uses:)/m)
  .slice(1)
  .map((block) => ({ name: /^name: (.+)$/m.exec(block)?.[1], id: /^ {8}id: (.+)$/m.exec(block)?.[1], text: block }));
const stepNamed = (name) => steps.find((step) => step.name === name);

test('the simulator status bar uses the override arguments accepted by Xcode 26.6', () => {
  const step = stepNamed('Prepare project and simulator');
  assert.ok(step, 'prepare step exists');
  const command = step.text.replace(/\s*\\\r?\n\s*/g, ' ');
  const args = command.match(/xcrun simctl status_bar\s+\S+\s+override ([^\r\n]+)/)?.[1];
  assert.equal(args, [
    '--time "9:41" --dataNetwork wifi',
    '--wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4',
    '--batteryState discharging --batteryLevel 100',
  ].join(' '));
});

test('screenshot tests wait for the amount field and keyboard without tapping the field', () => {
  const suite = read('Tests/FutariScreenshotTests/ScreenshotTests.swift');
  const wait = /private func waitForAmountKeyboard\([^\n]+\{([\s\S]*?)\n    \}/.exec(suite)?.[1] ?? '';
  assert.doesNotMatch(suite, /\bamount\s*\.\s*tap\s*\(/);
  assert.match(wait, /^\s*XCTAssertTrue\(amount\.waitForExistence\(timeout: 5\)\)\s+XCTAssertTrue\(app\.keyboards\.firstMatch\.waitForExistence\(timeout: 5\)\)\s*$/);
  assert.match(suite, /entry\.tap\(\)\s+let amount = app\.textFields\[[^\n]+\]\s+waitForAmountKeyboard\(amount, in: app\)\s+capture\("entry", style, in: app\)/);
  assert.match(suite, /entry\.tap\(\)\s+waitForAmountKeyboard\(amount, in: app\)\s+amount\.typeText\("1200"\)/);
});

test('every logged step tees its output to tmp/ci-logs and keeps the exit code', () => {
  for (const { id, title } of LOGGED_STEPS) {
    const step = stepNamed(title);
    assert.ok(step, `workflow has a step named "${title}"`);
    assert.equal(step.id, id);
    assert.match(step.text, /^ {10}set -eo pipefail$/m, `${id} sets pipefail so tee keeps the failure`);
    assert.match(step.text, new RegExp(`tee tmp/ci-logs/${id}\\.log`), `${id} tees into tmp/ci-logs/${id}.log`);
  }
});

test('the failure step runs on failure(), writes index.md and pushes ci-shots', () => {
  const step = stepNamed('Publish the failure report');
  assert.ok(step, 'failure step exists');
  assert.match(step.text, /^ {8}if: failure\(\)$/m);
  assert.match(step.text, /STEPS_JSON: \$\{\{ toJSON\(steps\) \}\}/);
  assert.match(step.text, /node \.github\/scripts\/ci-failure-report\.mjs/);
  assert.match(step.text, /bash \.github\/scripts\/publish-ci-shots\.sh/);
  assert.equal(steps.at(-1), step, 'the failure step is the last step');
  assert.match(read('.github/scripts/ci-failure-report.mjs'), /'index\.md'/);
});

test('the branch push exists once, in the shared script', () => {
  assert.equal(workflow.match(/refs\/heads\/ci-shots/g), null);
  assert.equal(workflow.match(/http\.extraHeader/g), null);
  const script = read('.github/scripts/publish-ci-shots.sh');
  assert.equal(script.match(/push --force/g)?.length, 1);
  assert.equal(script.match(/http\.extraHeader/g)?.length, 1);
  const callers = workflow.match(/publish-ci-shots\.sh/g)?.length;
  assert.equal(callers, 2, 'success publish and failure publish both call the shared script');
});

test('success index.md starts with 成功 and the commit SHA and keeps the screenshot list', () => {
  const script = read('.github/scripts/export-screenshots.py');
  const index = /index = \[\s*f"([^"]+)"/.exec(script)?.[1];
  assert.equal(index, "成功 {os.environ['GITHUB_SHA']}");
  assert.match(script, /!\[\{title\}（\{appearance\}）\]/);
});

test('failure report: first line is 失敗 + SHA, with run URL, failed step, error lines and log tails', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-report-'));
  const logDir = join(dir, 'logs');
  const outDir = join(dir, 'shots');
  mkdirSync(logDir);
  const buildLines = Array.from({ length: 300 }, (_, i) => `build line ${i + 1}`);
  buildLines.splice(10, 0, '/src/A.swift:3:4: error: cannot find x in scope', '** BUILD FAILED **', 'Testing failed:', '```');
  writeFileSync(join(logDir, 'prepare.log'), 'xcodegen generate\nSpec validation error: bad spec\n');
  writeFileSync(join(logDir, 'capture.log'), `${buildLines.join('\n')}\n`);
  const sha = 'a'.repeat(40);
  const runUrl = 'https://github.com/o/r/actions/runs/42';
  writeReport({
    logDir,
    outDir,
    sha,
    runUrl,
    steps: { prepare: { outcome: 'success' }, capture: { outcome: 'failure' }, export: { outcome: 'skipped' } },
  });

  const md = readFileSync(join(outDir, 'index.md'), 'utf8');
  assert.equal(md.split('\n')[0], `失敗 ${sha}`);
  assert.ok(md.includes(runUrl));
  assert.match(md, /失敗した手順: Build and capture \(capture\)/);
  for (const line of ['/src/A.swift:3:4: error: cannot find x in scope', '** BUILD FAILED **', 'Testing failed:', 'Spec validation error: bad spec']) {
    assert.ok(md.includes(line), `error line listed: ${line}`);
  }
  const tail = md.slice(md.indexOf('## ログの末尾150行'));
  assert.ok(tail.includes('build line 300') && tail.includes('build line 151'));
  assert.ok(!tail.includes('build line 150\n'), 'only the last 150 lines are shown');
  assert.match(tail, /ログなし（この手順は実行されませんでした）/);
  assert.deepEqual(readdirSync(outDir).sort(), ['capture.txt', 'index.md', 'prepare.txt']);
});

test('publish-ci-shots.sh does not emit masks or credentials into tee-captured logs', () => {
  const script = read('.github/scripts/publish-ci-shots.sh');
  const publish = stepNamed('Publish the screenshot branch');
  assert.ok(publish, 'publish step exists');
  const publishRun = publish.text.split(/^\s{8}run:\s*\|\r?\n/m)[1] ?? '';
  assert.doesNotMatch(script, /::add-mask::/);
  const encodeBasic = String.raw`basic="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"`;
  const outputCommands = script.split(/\r?\n/).filter((line) => line !== encodeBasic).join('\n');
  assert.doesNotMatch(outputCommands, /\b(?:echo|printf)\b[^\n]*\$\{?(?:basic|GH_TOKEN)\b/);
  assert.doesNotMatch(script, /\bset\s+-[^\n]*x/);
  assert.match(script, /GIT_CONFIG_KEY_0=http\.extraHeader/);
  assert.match(script, /GIT_CONFIG_VALUE_0="Authorization: Basic \$basic"/);
  assert.doesNotMatch(publishRun, /::add-mask::|GH_TOKEN|Authorization|\bbasic\b/);
});

test('writeReport drops mask and Authorization lines before publishing logs', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-mask-'));
  const logDir = join(dir, 'logs');
  const outDir = join(dir, 'failure');
  mkdirSync(logDir);
  const sample = 'FAKE-CI-TOKEN-NOT-A-SECRET';
  const basic = Buffer.from(`x-access-token:${sample}`).toString('base64');
  writeFileSync(
    join(logDir, 'publish.log'),
    [
      `::add-mask::${basic}`,
      'Authorization: Basic eC1h',
      'error: trace header Authorization: Custom fake-secret',
      `https://x-access-token:${sample}@github.com/o/r.git`,
      `error: leaked ${basic} in debug`,
      'remote: Permission denied',
    ].join('\r\n'),
  );
  writeReport({
    logDir,
    outDir,
    sha: 'b'.repeat(40),
    runUrl: 'https://github.com/o/r/actions/runs/99',
    steps: { publish: { outcome: 'failure' } },
  });

  assert.deepEqual(readdirSync(outDir).sort(), ['index.md', 'publish.txt']);
  for (const file of readdirSync(outDir)) {
    const output = readFileSync(join(outDir, file), 'utf8');
    assert.doesNotMatch(output, /::add-mask::|Authorization:|trace header/i, file);
    assert.ok(!output.includes(basic), `${file} must not contain the encoded token`);
    assert.ok(!output.includes(sample), `${file} must not contain the raw token`);
    assert.match(output, /Permission denied/, file);
    assert.match(output, /error: leaked \[REDACTED\] in debug/, file);
  }
});

test('failure report uses a dedicated clean directory separate from tmp/ci-shots', () => {
  const step = stepNamed('Publish the failure report');
  assert.ok(step, 'failure step exists');
  assert.match(step.text, /rm -rf tmp\/ci-failure/);
  assert.match(step.text, /node \.github\/scripts\/ci-failure-report\.mjs tmp\/ci-failure/);
  assert.match(step.text, /bash \.github\/scripts\/publish-ci-shots\.sh tmp\/ci-failure/);
  assert.doesNotMatch(step.text, /tmp\/ci-shots/);

  const script = read('.github/scripts/publish-ci-shots.sh');
  assert.match(script, /dir="\$\{1:-tmp\/ci-shots\}"/);
  assert.match(script, /cd "\$dir"/);
  assert.match(script, /rm -rf \.git/);
});

test('error line search and failed step detection', () => {
  assert.deepEqual(findErrorLines('ok\nerror: one\nerror: one\nxcodebuild: error: two\nfine\n'), ['error: one', 'xcodebuild: error: two']);
  assert.equal(findFailedStep({ a: { outcome: 'success' }, capture: { outcome: 'failure' } }).id, 'capture');
  assert.equal(findFailedStep({ a: { outcome: 'success' } }).title, '不明');
  const md = buildReport({ sha: 's', runUrl: 'u', steps: {}, logs: {} });
  assert.ok(md.startsWith('失敗 s\n'));
});
