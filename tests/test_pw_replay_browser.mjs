// Browser regression: play a real replay with Observatory's eval-free CSP.
// Usage: node tests/test_pw_replay_browser.mjs <bundle-directory> <replay-file>
// Set PLAYWRIGHT_MODULE to an installed Playwright module when not on NODE_PATH.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const moduleName = process.env.PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = await import(path.isAbsolute(moduleName) ? pathToFileURL(moduleName).href : moduleName);
const [bundleArg, replayArg] = process.argv.slice(2);
assert(bundleArg && replayArg, 'Pass the built browser bundle and a real replay file');
const bundle = path.resolve(bundleArg);
const replay = path.resolve(replayArg);
const csp = "default-src 'none'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data:; connect-src 'self' https: http:; media-src 'self' blob:; worker-src 'self' blob:; frame-src 'self'";
const server = http.createServer((req, res) => {
  const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = name === '/episode.replay' ? replay : path.resolve(bundle, '.' + (name === '/' ? '/index.html' : name));
  if (file !== replay && !file.startsWith(bundle + path.sep)) { res.writeHead(403); res.end(); return; }
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
  const mime = {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.png':'image/png','.webp':'image/webp'};
  res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Content-Security-Policy', csp);
  fs.createReadStream(file).pipe(res);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await chromium.launch({headless:true,args:['--enable-webgl','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  for (const touch of [false, true]) {
    const context = await browser.newContext({viewport:{width:1280,height:800},hasTouch:touch,isMobile:touch});
    const page = await context.newPage();
    const errors = [], states = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => {
      const text = m.text();
      if (text.startsWith('pw-state:')) states.push(JSON.parse(text.slice(9)));
      if (m.type() === 'error' || /hash mismatch|desync/i.test(text)) errors.push(text);
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/?replay=/episode.replay&speed=4`);
    await page.waitForFunction(() => document.getElementById('boot')?.classList.contains('gone'), {}, {timeout:60000});
    const deadline = Date.now() + 30000;
    while (!errors.length && (!states.length || states.at(-1).tick < 64) && Date.now() < deadline) {
      await page.waitForTimeout(100);
    }
    assert.deepEqual(errors, [], `Replay failed under CSP (${touch ? 'touch' : 'mouse'})`);
    assert(states.some(s => s.tick >= 64), 'Replay did not advance through its first 64 ticks');
    const output = process.env.REPLAY_SCREENSHOT_DIR;
    if (output) {
      fs.mkdirSync(output, {recursive:true});
      await page.screenshot({path:path.join(output, touch ? 'replay-touch.png' : 'replay-desktop.png')});
    }
    console.log(JSON.stringify({pointer:touch?'touch':'mouse',lastTick:states.at(-1).tick,errors}));
    await context.close();
  }
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
