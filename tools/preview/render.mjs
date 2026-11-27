import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const previewDir = path.join(root, 'tools', 'preview');
const outputDir = path.join(root, 'docs', 'preview');
const screens = ['home', 'budget', 'paywall'];
const requestedScreen = process.argv[2];
if (requestedScreen && !screens.includes(requestedScreen)) {
  throw new Error('Choose home, budget or paywall.');
}

function findBrowser() {
  const override = process.env.PREVIEW_BROWSER;
  if (override && existsSync(override)) return override;
  const candidates = [
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join(process.env.LOCALAPPDATA || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  ];
  const found = candidates.find((candidate) => candidate && existsSync(candidate));
  if (!found) {
    throw new Error('No local Chromium browser (Chrome or Edge) found. Set PREVIEW_BROWSER to the executable path.');
  }
  return found;
}

function pngDimensions(buffer) {
  const signature = '89504e470d0a1a0a';
  if (buffer.length < 24 || buffer.subarray(0, 8).toString('hex') !== signature) {
    throw new Error('Output is not a valid PNG file.');
  }
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

const browser = findBrowser();
mkdirSync(outputDir, { recursive: true });
const profileDir = mkdtempSync(path.join(os.tmpdir(), 'futari-preview-'));

try {
  for (const screen of requestedScreen ? [requestedScreen] : screens) {
    const htmlPath = path.join(previewDir, `${screen}.html`);
    const outPath = path.join(outputDir, `${screen}-390.png`);
    const args = [
      '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-background-networking',
      '--disable-extensions',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--window-size=390,844',
      `--user-data-dir=${profileDir}`,
      `--screenshot=${outPath}`,
      pathToFileURL(htmlPath).href,
    ];
    execFileSync(browser, args, { stdio: 'pipe', windowsHide: true, timeout: 30000 });
    const bytes = readFileSync(outPath);
    const { width, height } = pngDimensions(bytes);
    if (width !== 390) {
      throw new Error(`${path.relative(root, outPath)} has width ${width}, expected 390.`);
    }
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    console.log(`${path.relative(root, outPath)} ${width}x${height} ${bytes.length}B sha256=${sha256}`);
  }
} finally {
  rmSync(profileDir, { recursive: true, force: true });
}
