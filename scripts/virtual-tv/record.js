// Records the TV app on the virtual TV (vtv.sh): sets up a scenario, opens
// the app in headless Chromium at 1920x1080, presses the remote's keys and
// writes an MP4 (and screenshots).  Nothing shows on this computer's screen.
//
//   node scripts/virtual-tv/record.js --scenario c9 \
//       --steps 'wait:2500 down*2 shot:home.png ok wait:1500 back' --mp4 out.mp4
//
// Steps: up, down, left, right, ok, back (each can take *N), wait:MS,
// shot:FILE.png (a full-size screenshot), and focus:ACTION (focus the row
// with that data-action, like a user scrolling to it).  --keep uses the
// virtual TV as it is instead of setting it up again.  --width 960 sets
// the MP4's width (default 960, the README size).
// Needs Playwright (npm i playwright) and ffmpeg.
'use strict';
const { execFileSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

let chromium;
try { ({ chromium } = require('playwright')); } catch (e) {
  ({ chromium } = require(path.join(os.homedir(), '.cache/lg-virtual-tv-node/node_modules/playwright')));
}

const arg = (name, def) => { const i = process.argv.indexOf('--' + name); return i > 0 ? process.argv[i + 1] : def; };
const flag = (name) => process.argv.includes('--' + name);
const SCENARIO = arg('scenario', 'c2');
const STEPS = arg('steps', 'wait:3000');
const MP4 = arg('mp4', '') && path.resolve(arg('mp4'));
const WIDTH = Number(arg('width', 960));
const PORT = Number(arg('port', 8731));
const VTV = path.join(__dirname, 'vtv.sh');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const KEYS = { up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight', ok: 'Enter' };

(async () => {
  if (!flag('keep')) { execFileSync(VTV, ['setup', SCENARIO], { stdio: 'inherit' }); }
  const server = spawn(process.execPath, [path.join(__dirname, 'server.js'), String(PORT)], { stdio: 'ignore' });
  await sleep(700);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'vtv-rec-'));
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: MP4 ? { dir: work, size: { width: 1920, height: 1080 } } : undefined
  });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.error('app error: ' + e.message));
  await page.goto('http://127.0.0.1:' + PORT + '/');
  for (const step of STEPS.trim().split(/\s+/)) {
    const [name, n] = step.split('*');
    const times = Number(n || 1);
    for (let i = 0; i < times; i++) {
      if (name.startsWith('wait:')) { await page.waitForTimeout(Number(name.slice(5))); continue; }
      if (name.startsWith('shot:')) { await page.screenshot({ path: path.resolve(name.slice(5)) }); console.log('wrote ' + name.slice(5)); continue; }
      if (name.startsWith('focus:')) {
        await page.evaluate((a) => document.querySelector('[data-action="' + a + '"]').focus(), name.slice(6));
        await page.waitForTimeout(300); continue;
      }
      if (name === 'back') {
        // The remote's BACK key (461), which no desktop key sends
        await page.evaluate(() => {
          const e = new KeyboardEvent('keydown', { bubbles: true, cancelable: true });
          Object.defineProperty(e, 'keyCode', { get: () => 461 });
          Object.defineProperty(e, 'which', { get: () => 461 });
          (document.activeElement || document.body).dispatchEvent(e);
        });
      } else if (KEYS[name]) {
        await page.keyboard.press(KEYS[name]);
      } else {
        throw new Error('Unknown step ' + step);
      }
      await page.waitForTimeout(450);
    }
  }
  const video = MP4 ? await page.video().path() : '';
  await ctx.close();
  await browser.close();
  server.kill();
  if (MP4) {
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-ss', '0.4', '-i', video, '-vf', 'fps=12,scale=' + WIDTH + ':-2:flags=lanczos',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '24', '-preset', 'slow', '-movflags', '+faststart', '-an', MP4]);
    console.log('wrote ' + MP4);
  }
  fs.rmSync(work, { recursive: true, force: true });
})().catch((e) => { console.error(e); process.exit(1); });
