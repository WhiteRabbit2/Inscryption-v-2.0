// Общий код для браузерных тестов: запуск Chromium, подмена CDN локальными файлами, сбор ошибок.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.join(here, '..');
const require = createRequire(import.meta.url);

export async function loadPlaywright() {
  for (const p of ['playwright', '/opt/node22/lib/node_modules/playwright/index.js']) {
    try { return require(p); } catch (e) { /* пробуем дальше */ }
  }
  throw new Error('Playwright не найден. Установи: npm i -D playwright');
}

// В тестах Google Fonts недоступен — отдаём Handjet из папки игры на Godot, чтобы скриншоты были с настоящим шрифтом.
function handjetCss() {
  const dir = path.join(ROOT, '..', 'game', 'assets', 'fonts');
  const face = (file, w) => {
    const p = path.join(dir, file);
    if (!fs.existsSync(p)) return '';
    return `@font-face{font-family:'Handjet';font-weight:${w};src:url(data:font/ttf;base64,${fs.readFileSync(p).toString('base64')}) format('truetype');}`;
  };
  return face('Handjet-400.ttf', 400) + face('Handjet-600.ttf', 500) + face('Handjet-600.ttf', 600) + face('Handjet-700.ttf', 700);
}

function findThree() {
  const cands = [process.env.THREE_PATH, path.join(ROOT, 'node_modules/three/build/three.min.js')].filter(Boolean);
  return cands.find(p => fs.existsSync(p)) || null;
}

export async function openGame({ width = 1280, height = 720, mobile = false, clearStorage = true } = {}) {
  const { chromium } = await loadPlaywright();
  const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome'].find(p => fs.existsSync(p));
  const browser = await chromium.launch({ executablePath: exe, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
  const context = await browser.newContext({ viewport: { width, height }, hasTouch: mobile, isMobile: mobile, deviceScaleFactor: 1 });
  const page = await context.newPage();
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  page.on('pageerror', e => errors.push('pageerror: ' + e.message));
  const three = findThree();
  if (three) await page.route('**/three.min.js', r => r.fulfill({ path: three, contentType: 'application/javascript' }));
  const fontCss = handjetCss(); await page.route(/fonts\.(googleapis|gstatic)\.com/, r => r.fulfill({ status: 200, contentType: 'text/css', body: fontCss }));
  await page.goto('file://' + path.join(ROOT, 'index.html'));
  if (clearStorage) { await page.evaluate(() => { try { localStorage.clear(); } catch (e) {} }); await page.reload(); }
  await page.waitForFunction(() => window.__game, null, { timeout: 15000 });
  return { browser, page, errors };
}
