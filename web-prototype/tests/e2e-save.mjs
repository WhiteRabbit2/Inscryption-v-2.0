// Проверка сохранений: перезагрузка страницы посреди забега и посреди боя, затем «Продолжить забег».
import { openGame } from './browser.mjs';

const { browser, page, errors } = await openGame({});
const st = () => page.evaluate(() => __game.state());
// Условие проверяется и ход делается за один вызов внутри страницы — иначе бот может проскочить нужный момент.
const until = async (fn, max = 3000) => {
  for (let i = 0; i < max; i++) {
    const r = await page.evaluate((src) => {
      const s = __game.state();
      if (new Function('s', 'return (' + src + ')(s)')(s)) return { done: true, s };
      __game.autoStep();
      return { done: false };
    }, fn.toString());
    if (r.done) return r.s;
    await page.waitForTimeout(8);
  }
  throw new Error('не дождались состояния');
};
let fails = 0;
const check = (ok, msg) => { console.log((ok ? 'OK   ' : 'FAIL ') + msg); if (!ok) fails++; };

await page.evaluate(() => __game.setSpeed(40));
// 1. играем до карты после первого боя
const s1 = await until(s => s.input === 'map' && s.run && s.run.visited >= 1);
const before = await page.evaluate(() => ({ deck: __game.G.run.deck.length, pos: __game.G.run.pos, visited: __game.G.run.visited.slice(), items: __game.G.run.items.slice() }));
await page.reload();
await page.waitForFunction(() => window.__game);
await page.waitForTimeout(500);
const hasContinue = await page.evaluate(() => [...document.querySelectorAll('#screen button')].some(b => b.textContent.includes('Продолжить')));
check(hasContinue, 'после перезагрузки есть кнопка «Продолжить забег»');
await page.click('#scr-0');
await page.evaluate(() => __game.setSpeed(40));
const s2 = await until(s => s.input === 'map');
const after = await page.evaluate(() => ({ deck: __game.G.run.deck.length, pos: __game.G.run.pos, visited: __game.G.run.visited.slice(), items: __game.G.run.items.slice() }));
check(JSON.stringify(before) === JSON.stringify(after), 'забег восстановился как был: ' + JSON.stringify(after) + (JSON.stringify(before) === JSON.stringify(after) ? '' : ' (до перезагрузки: ' + JSON.stringify(before) + ')'));

// 2. перезагрузка посреди боя — бой начинается заново в том же узле
const sb = await until(s => s.battle && s.battle.turn >= 2 && s.input === 'battle');
const node = sb.run.pos;
await page.reload();
await page.waitForFunction(() => window.__game);
await page.waitForTimeout(500);
await page.click('#scr-0');
await page.evaluate(() => __game.setSpeed(40));
const sc = await until(s => s.battle && s.input === 'battle');
check(sc.run.pos === node && sc.battle.turn === 1, 'бой после перезагрузки начался заново в том же узле');

// 3. новый забег стирает старый
await page.reload();
await page.waitForFunction(() => window.__game);
await page.waitForTimeout(500);
await page.click('#scr-1');
await page.evaluate(() => __game.setSpeed(40));
const sn = await until(s => s.input === 'map');
check(sn.run.visited === 0, '«Новый забег» начинает с нуля');

const fin = await st();
const all = errors.concat(fin.errors);
check(all.length === 0, 'нет ошибок в консоли' + (all.length ? ': ' + all.join(' | ') : ''));
await browser.close();
process.exit(fails ? 1 : 0);
