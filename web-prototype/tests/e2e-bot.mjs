// Бот проходит несколько забегов целиком через настоящий интерфейс игры (в ускоренном режиме).
// Проверяет: нет ошибок в консоли, бои заканчиваются, игра нигде не зависает.
// Запуск: node tests/e2e-bot.mjs [число_забегов]
import { openGame } from './browser.mjs';

const RUNS = +(process.argv[2] || 3);
const { browser, page, errors } = await openGame({ width: 1280, height: 720 });
const st = () => page.evaluate(() => __game.state());
await page.evaluate(() => __game.setSpeed(40));

let runs = 0, wins = 0, steps = 0, stuck = 0, lastSig = '', sameFor = 0;
const log = [];
let curRun = null;
const t0 = Date.now();
while (runs < RUNS) {
  const s = await st();
  if (s.errors.length) break;
  // следим за забегом
  if (s.run && (!curRun || s.run.pos !== curRun.lastPos)) {
    const type = await page.evaluate(() => __game.G.run.map.nodes[__game.G.run.pos].type);
    if (!curRun) curRun = { path: [], lastPos: null };
    if (s.run.pos !== curRun.lastPos) { curRun.path.push(type); curRun.lastPos = s.run.pos; }
  }
  if (s.screen) {
    const title = await page.evaluate(() => (document.querySelector('#screen h1, #screen h2') || {}).textContent || '');
    if (/Свечи погасли|Забег пройден/.test(title) && curRun && !curRun.done) {
      curRun.done = true; runs++;
      const won = /Забег пройден/.test(title);
      if (won) wins++;
      log.push(`забег ${runs}: ${won ? 'ПОБЕДА' : 'смерть'} — ${curRun.path.join(' → ')}`);
      console.log(log[log.length - 1]);
      curRun = null;
    }
  }
  const sig = JSON.stringify([s.mode, s.busy, s.input, s.dialog, s.screen, s.run, s.battle]);
  if (sig === lastSig) sameFor++; else { sameFor = 0; lastSig = sig; }
  if (sameFor > 1500) { stuck++; console.log('ЗАВИСАНИЕ:', sig); break; }
  await page.evaluate(() => __game.autoStep());
  steps++;
  await page.waitForTimeout(8);
  if (Date.now() - t0 > 25 * 60 * 1000) { console.log('Слишком долго'); break; }
}
const fin = await st();
console.log(`Итого: забегов ${runs}, побед ${wins}, шагов ${steps}, время ${((Date.now() - t0) / 1000).toFixed(0)} с`);
const all = errors.concat(fin.errors);
if (all.length) console.log('ОШИБКИ:\n' + all.join('\n'));
else console.log('Ошибок в консоли нет.');
await browser.close();
process.exit(all.length || stuck || runs < RUNS ? 1 : 0);
