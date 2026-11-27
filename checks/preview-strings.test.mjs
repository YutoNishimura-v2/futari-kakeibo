import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const previewScreens = ['home', 'budget', 'paywall'];
const japaneseCharPattern = /[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]/;

function listFiles(dir, extension) {
  const results = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listFiles(fullPath, extension));
    } else if (entry.name.endsWith(extension)) {
      results.push(fullPath);
    }
  }
  return results;
}

function decodeHtmlEntities(text) {
  return text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
}

function extractVisibleJapaneseStrings(html) {
  const bodyMatch = /<body\b[^>]*>([\s\S]*?)<\/body>/i.exec(html);
  const body = bodyMatch ? bodyMatch[1] : html;
  const cleaned = body
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, ' ');

  const texts = [];
  for (const chunk of cleaned.split(/<[^>]+>/g)) {
    const normalized = decodeHtmlEntities(chunk).replace(/\s+/g, ' ').trim();
    if (normalized && japaneseCharPattern.test(normalized)) {
      texts.push(normalized);
    }
  }
  return texts;
}

function scanSwiftCode(source, startIndex, stopOnCloseParen, literals, templates) {
  let i = startIndex;
  let parenDepth = stopOnCloseParen ? 1 : 0;

  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];

    if (ch === '/' && next === '/') {
      i += 2;
      while (i < source.length && source[i] !== '\n') i += 1;
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      let commentDepth = 1;
      while (i < source.length && commentDepth > 0) {
        if (source[i] === '/' && source[i + 1] === '*') {
          commentDepth += 1;
          i += 2;
        } else if (source[i] === '*' && source[i + 1] === '/') {
          commentDepth -= 1;
          i += 2;
        } else {
          i += 1;
        }
      }
      continue;
    }
    if (stopOnCloseParen) {
      if (ch === '(') {
        parenDepth += 1;
      } else if (ch === ')') {
        parenDepth -= 1;
        if (parenDepth === 0) return i + 1;
      }
    }
    if (ch === '"') {
      const multiline = source.slice(i, i + 3) === '"""';
      const quoteLen = multiline ? 3 : 1;
      i += quoteLen;
      const parts = [];
      let currentText = '';
      let hasInterpolation = false;

      while (i < source.length) {
        if (multiline ? source.slice(i, i + 3) === '"""' : source[i] === '"') {
          i += quoteLen;
          break;
        }
        if (source[i] === '\\') {
          const esc = source[i + 1];
          if (esc === '(') {
            hasInterpolation = true;
            if (currentText) {
              parts.push({ kind: 'text', value: currentText });
              currentText = '';
            }
            const exprStart = i + 2;
            const nestedLiterals = [];
            const exprEnd = scanSwiftCode(source, exprStart, true, nestedLiterals, templates);
            const exprCode = source.slice(exprStart, exprEnd - 1);
            for (const nested of nestedLiterals) literals.push(nested);
            parts.push({ kind: 'expr', value: exprCode, literals: nestedLiterals });
            i = exprEnd;
            continue;
          }
          if (esc === 'n') currentText += '\n';
          else if (esc === 'r') currentText += '\r';
          else if (esc === 't') currentText += '\t';
          else if (esc) currentText += esc;
          i += 2;
          continue;
        }
        currentText += source[i];
        i += 1;
      }
      if (currentText) {
        parts.push({ kind: 'text', value: currentText });
      }
      if (!hasInterpolation) {
        literals.push(parts.map((p) => p.value).join(''));
      } else {
        templates.push(parts);
      }
      continue;
    }
    i += 1;
  }
  return i;
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildSwiftMatcher(swiftSources) {
  const literalSet = new Set();
  const templateRegexes = [];
  const allCode = swiftSources.join('\n');

  for (const source of swiftSources) {
    const literals = [];
    const templates = [];
    scanSwiftCode(source, 0, false, literals, templates);
    for (const lit of literals) literalSet.add(lit);
    for (const parts of templates) {
      const staticText = parts.filter((p) => p.kind === 'text').map((p) => p.value).join('');
      if (!japaneseCharPattern.test(staticText)) continue;
      let pattern = '^';
      for (const part of parts) {
        if (part.kind === 'text') {
          pattern += escapeRegExp(part.value);
          continue;
        }
        const expr = part.value;
        const japaneseLits = part.literals.filter((lit) => japaneseCharPattern.test(lit));
        if (japaneseLits.length > 0) {
          pattern += `(?:${japaneseLits.map(escapeRegExp).join('|')})`;
        } else if (/\byen\b|amount|price/.test(expr)) {
          pattern += ' ?[0-9,]+円';
        } else if (/names\b|payer/.test(expr)) {
          pattern += '[ぁ-んァ-ヶー一-龠]{1,8}';
        } else if (/formatted\(/.test(expr)) {
          pattern += '-?[0-9]+';
        } else {
          pattern += '[^\\n。]{0,30}';
        }
      }
      pattern += '$';
      templateRegexes.push(new RegExp(pattern));
    }
  }

  const supportsYen = literalSet.has('円') && /\bvar yen:\s*String\b/.test(allCode);
  const supportsJapaneseYearMonth = /\bjapaneseDate\b/.test(allCode) && /\byear:\s*2026,\s*month:\s*6\b/.test(allCode);

  return function matchesSwiftSource(text) {
    if (literalSet.has(text)) return true;
    if (supportsYen && /^-?[0-9,]+円$/.test(text)) return true;
    if (supportsJapaneseYearMonth && /^\d{4}年\d{1,2}月$/.test(text)) return true;
    return templateRegexes.some((regex) => regex.test(text));
  };
}

function findMissingPreviewStrings(htmlEntries, swiftSources) {
  const matches = buildSwiftMatcher(swiftSources);
  const missing = [];
  for (const { file, html } of htmlEntries) {
    const visibleStrings = extractVisibleJapaneseStrings(html);
    for (const text of visibleStrings) {
      if (!matches(text)) {
        missing.push({ file, text });
      }
    }
  }
  return missing;
}

const swiftSources = listFiles(path.join(root, 'Sources'), '.swift').map((file) => readFileSync(file, 'utf8'));

test('every visible Japanese string in tools/preview/*.html appears in the Swift source', () => {
  const htmlEntries = previewScreens.map((screen) => {
    const file = path.join(root, 'tools', 'preview', `${screen}.html`);
    const html = readFileSync(file, 'utf8');
    const visible = extractVisibleJapaneseStrings(html);
    assert.ok(visible.length > 0, `Expected visible Japanese strings in ${screen}.html`);
    return { file: `tools/preview/${screen}.html`, html };
  });

  const missing = findMissingPreviewStrings(htmlEntries, swiftSources);
  assert.deepEqual(missing, []);
  const catalog = JSON.parse(readFileSync(path.join(root, 'FutariKakeibo.storekit'), 'utf8'));
  const [monthly, yearly] = catalog.subscriptionGroups[0].subscriptions.map(({ displayPrice }) => Number(displayPrice));
  const paywall = htmlEntries.find(({ file }) => file.endsWith('/paywall.html'));
  const displayedPrices = [...paywall.html.matchAll(/class="option-price">([0-9,]+)円</g)]
    .map(([, price]) => Number(price.replaceAll(',', '')));
  assert.deepEqual(displayedPrices, [monthly, yearly]);
  const savings = Math.floor((1 - yearly / (monthly * 12)) * 100);
  assert.ok(paywall.html.includes('年額は月額12か月分より約' + savings + '%お得'));
});

test('source check fails when a preview HTML fixture contains a Japanese string missing from Swift sources', () => {
  const badFixture = {
    file: 'fixture/bad-preview.html',
    html: '<body><div>ふたりの家計簿</div><p>Swiftに存在しない文字列</p><span>あおいから 3,110円 借りる</span></body>',
  };
  const missing = findMissingPreviewStrings([badFixture], swiftSources);
  assert.deepEqual(missing.map((item) => item.text), [
    'Swiftに存在しない文字列',
    'あおいから 3,110円 借りる',
  ]);
});
