// Достаёт <script id="game-logic"> из index.html и выполняет его в изолированном контексте Node.
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export function loadLogic(file = process.env.GAME_FILE || path.join(here, '..', 'index.html')) {
  const html = fs.readFileSync(file, 'utf8');
  const m = /<script id="game-logic">([\s\S]*?)<\/script>/.exec(html);
  if (!m) throw new Error('Не нашёл <script id="game-logic"> в ' + file);
  const ctx = { console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(m[1], ctx, { filename: 'game-logic.js' });
  return ctx.GameLogic;
}
