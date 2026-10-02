// Симуляция забегов ботом: проверяет, что бои всегда заканчиваются, и меряет баланс.
// Запуск: node tests/sim.mjs [число_игроков]
import { loadLogic } from './load-logic.mjs';

const L = loadLogic();
const PLAYERS = +(process.argv[2] || 300);
const SMART = process.argv[3] !== 'simple';
const MAX_ATTEMPTS = 8;

const stat = { battles: 0, won: 0, lost: 0, maxTurns: 0, turnSum: 0, byEnc: {}, runs: 0, runWins: 0, attemptsToWin: [], deaths: {}, teeth: 0, errors: 0 };

function playBattle(run, node) {
  for (;;) {
    const b = L.createBattle(L.battleOptions(run, node));
    const r = L.botBattle(b, 4000, SMART);
    stat.battles++;
    if (!b.result) { stat.errors++; console.error('Бой не закончился!', node.encounter, r); process.exit(1); }
    stat.maxTurns = Math.max(stat.maxTurns, b.turn);
    stat.turnSum += b.turn;
    const key = node.type === 'boss' ? 'BOSS' : node.encounter + (node.type === 'hard' ? '*' : '');
    const e = stat.byEnc[key] || (stat.byEnc[key] = { n: 0, lost: 0, turns: 0 });
    e.n++; e.turns += b.turn;
    const fin = L.finishBattle(run, b);
    if (b.result === 'won') { stat.won++; return true; }
    stat.lost++; e.lost++;
    if (fin.dead) return false;
  }
}

function playRun(seed, deathPool, firstRun) {
  const run = L.newRun({ seed, tutorial: firstRun });
  const r = L.makeRng(seed ^ 0xabcdef);
  for (let step = 0; step < 50; step++) {
    const next = L.nextNodes(run);
    if (!next.length) return { win: true, run };
    const node = r.pick(next);
    L.moveTo(run, node.id);
    if (['battle', 'hard', 'boss'].includes(node.type)) {
      const ok = playBattle(run, node);
      if (!ok) { stat.deaths[node.type === 'boss' ? 'BOSS' : 'layer' + node.layer] = (stat.deaths[node.type === 'boss' ? 'BOSS' : 'layer' + node.layer] || 0) + 1; return { win: false, run }; }
      if (node.type === 'hard') L.botRunChoice(run, node.trophy || (L.trophyOffer(run, node, deathPool), node.trophy), deathPool);
      if (node.type === 'boss') { L.completeNode(run, node.id); return { win: true, run }; }
    } else L.botRunChoice(run, node, deathPool);
    L.completeNode(run, node.id);
    // сохранение/загрузка посреди забега должны работать
    const s = L.serializeRun(run);
    const back = L.deserializeRun(s);
    if (!back) { console.error('Сохранение сломалось'); process.exit(1); }
  }
  throw new Error('Забег не закончился');
}

for (let p = 0; p < PLAYERS; p++) {
  const deathPool = [];
  let won = false;
  for (let a = 1; a <= MAX_ATTEMPTS; a++) {
    stat.runs++;
    const res = playRun(p * 7919 + a * 104729 + 1, deathPool, a === 1);
    stat.teeth += res.run.stats.teeth;
    if (res.win) { stat.runWins++; stat.attemptsToWin.push(a); won = true; break; }
    // карта смерти из трёх случайных карт колоды
    const d = res.run.deck;
    const byCost = d.slice().sort((x, y) => (x.blood * 3 + x.bones) - (y.blood * 3 + y.bones))[0];
    const byStat = d.slice().sort((x, y) => (y.atk * 2 + y.hp) - (x.atk * 2 + x.hp))[0];
    const bySig = d.slice().sort((x, y) => y.sigils.length - x.sigils.length)[0];
    deathPool.push(L.makeDeathCard(byCost, byStat, bySig, L.deathName(byCost, byStat, bySig)));
  }
  if (!won) stat.attemptsToWin.push(99);
}

const hist = {};
for (const a of stat.attemptsToWin) hist[a] = (hist[a] || 0) + 1;
const within = n => (stat.attemptsToWin.filter(a => a <= n).length / PLAYERS * 100).toFixed(1) + '%';
console.log('Бот:', SMART ? 'умный' : 'простой', 'игроков:', PLAYERS, 'забегов:', stat.runs, 'побед в забегах:', (stat.runWins / stat.runs * 100).toFixed(1) + '%');
console.log('Прошли за 1 попытку:', within(1), 'за ≤2:', within(2), 'за ≤3:', within(3));
console.log('Попыток до победы:', JSON.stringify(hist));
console.log('Боёв:', stat.battles, 'проиграно:', stat.lost, 'средняя длина:', (stat.turnSum / stat.battles).toFixed(1), 'максимум ходов:', stat.maxTurns);
console.log('Где умирают:', JSON.stringify(stat.deaths));
console.log('Зубов за забег в среднем:', (stat.teeth / stat.runs).toFixed(1));
const rows = Object.entries(stat.byEnc).sort();
for (const [k, e] of rows) console.log('  ', k.padEnd(12), 'боёв', String(e.n).padStart(5), ' проигрышей', ((e.lost / e.n) * 100).toFixed(1).padStart(5) + '%', ' ходов', (e.turns / e.n).toFixed(1));
if (stat.errors) process.exit(1);
