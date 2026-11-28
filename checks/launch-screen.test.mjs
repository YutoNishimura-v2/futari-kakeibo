import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const project = readFileSync(new URL('../project.yml', import.meta.url), 'utf8');
const appSources = new URL('../Sources/FutariKakeibo/', import.meta.url);
const appTarget = project.match(/^  FutariKakeibo:\r?\n(?:^ {4}.*\r?\n)*/m)?.[0] ?? '';

test('the app generates a launch screen dictionary without a launch storyboard', () => {
  assert.match(appTarget, /^    info:\r?\n      path: FutariKakeibo-Info\.plist\r?\n      properties:\r?\n(?:^ {8,}.*\r?\n)*?^        UILaunchScreen:\r?\n          UIColorName: LaunchBackground\s*$/m);
  assert.doesNotMatch(project, /UILaunchStoryboardName|LaunchScreen\.storyboard/);
  assert.equal(existsSync(new URL('LaunchScreen.storyboard', appSources)), false);
});

test('the launch background is bundled with the app for light and dark appearances', () => {
  const catalog = new URL('Assets.xcassets/', appSources);
  const colorSet = new URL('LaunchBackground.colorset/Contents.json', catalog);
  const { colors } = JSON.parse(readFileSync(colorSet, 'utf8'));
  assert.match(appTarget, /^      - path: Sources\/FutariKakeibo\r?$/m);
  assert.equal(JSON.parse(readFileSync(new URL('Contents.json', catalog), 'utf8')).info.version, 1);
  assert.deepEqual(colors.map(({ appearances, color, idiom }) => ({
    appearance: appearances?.[0],
    colorSpace: color['color-space'],
    components: color.components,
    idiom,
  })), [
    {
      appearance: undefined,
      colorSpace: 'srgb',
      components: { red: '0.9490196078', green: '0.9490196078', blue: '0.9686274510', alpha: '1.000' },
      idiom: 'universal',
    },
    {
      appearance: { appearance: 'luminosity', value: 'dark' },
      colorSpace: 'srgb',
      components: { red: '0.000', green: '0.000', blue: '0.000', alpha: '1.000' },
      idiom: 'universal',
    },
  ]);
});

test('the launch asset catalog can compile without an app icon', () => {
  const baseSettings = appTarget.match(/^    settings:\r?\n      base:\r?\n(?<body>(?:^ {8}[^\r\n]*\r?\n)+)/m)?.groups.body ?? '';
  const iconName = baseSettings.match(/^        ASSETCATALOG_COMPILER_APPICON_NAME: ([^\r\n]+)$/m)?.[1];
  const iconSet = new URL('Assets.xcassets/AppIcon.appiconset/Contents.json', appSources);
  assert.ok(
    iconName === '""' || ((iconName === undefined || iconName === 'AppIcon') && existsSync(iconSet)),
    'The app target must clear the AppIcon setting until the AppIcon asset is present',
  );
});
