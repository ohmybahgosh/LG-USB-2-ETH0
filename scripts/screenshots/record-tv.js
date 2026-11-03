// Records the README's TV app animation (assets/app-tv.gif) on a real TV:
// it scrolls down the menu, opens "Wi-Fi as a backup" and "Report for
// GitHub", closes each with BACK, and scrolls back up, so the GIF loops.
// Only those two rows are ever opened, and only after checking they have
// the focus, so nothing on the TV changes.  It shows the TV's real status.
//
// The TV's web app inspector listens on port 9998, for the TV itself only,
// so reach it through SSH.  Open the app on the TV first, then:
//
//   ssh -N -L 19998:127.0.0.1:9998 root@TV &
//   node scripts/screenshots/record-tv.js [--mp4 FILE]
//
// Needs Node with the ws package (npm i ws) and ffmpeg.
'use strict';
const WebSocket = require('ws');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

const ROOT = path.resolve(__dirname, '../..');
const PORT = process.env.LGU2E_INSPECT_PORT || 19998;
const mp4Arg = process.argv.indexOf('--mp4');
const MP4 = mp4Arg > 0 ? path.resolve(process.argv[mp4Arg + 1]) : '';
const KEYS = { up: [38, 'ArrowUp'], down: [40, 'ArrowDown'], ok: [13, 'Enter'], back: [461, 'GoBack'] };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pages() {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${PORT}/json`, (res) => {
      let b = '';
      res.on('data', (c) => { b += c; });
      res.on('end', () => { try { resolve(JSON.parse(b)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

(async () => {
  const page = (await pages()).find((p) => p.title === 'LG-USB-2-ETH0');
  if (!page) { throw new Error('Open the LG-USB-2-ETH0 app on the TV first.'); }
  const ws = new WebSocket(page.webSocketDebuggerUrl.replace(/127\.0\.0\.1:\d+/, `127.0.0.1:${PORT}`));
  await new Promise((r) => ws.on('open', r));
  let id = 0;
  const pending = {};
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'lgu2e-tv-'));
  const frames = [];
  ws.on('message', (m) => {
    const d = JSON.parse(m);
    if (d.id && pending[d.id]) { pending[d.id](d.result || {}); delete pending[d.id]; return; }
    if (d.method === 'Page.screencastFrame') {
      const n = String(frames.length).padStart(5, '0');
      fs.writeFileSync(path.join(work, n + '.jpg'), Buffer.from(d.params.data, 'base64'));
      frames.push([n, d.params.metadata.timestamp]);
      send('Page.screencastFrameAck', { sessionId: d.params.sessionId });
    }
  });
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
  const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true })).result.value;
  const key = async (k) => {
    const [code, name] = KEYS[k];
    for (const type of ['rawKeyDown', 'keyUp']) {
      await send('Input.dispatchKeyEvent', { type, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code, key: name, code: name });
    }
  };
  const focused = () => evaluate('document.activeElement && document.activeElement.getAttribute("data-action")');
  const overlayOpen = async () => !/hidden/.test(await evaluate('document.getElementById("overlay").className'));
  // Press OK only on the row we expect, so nothing else can be switched
  const open = async (action) => {
    const f = await focused();
    if (f !== action) { throw new Error(`The focus is on ${f}, not ${action}.  Nothing was opened.`); }
    await key('ok');
  };
  const to = async (action, dir) => {
    for (let i = 0; i < 12 && (await focused()) !== action; i++) { await key(dir); await sleep(550); }
  };

  if (await overlayOpen()) { await key('back'); await sleep(500); }
  await to('boot', 'up');
  await sleep(800);
  await send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });
  try {
    await sleep(1300);
    await to('wifi', 'down');
    await sleep(300); await open('wifi'); await sleep(2600);
    await key('back'); await sleep(900);
    await to('report', 'down');
    await sleep(300); await open('report'); await sleep(3400);
    await key('back'); await sleep(900);
    await to('boot', 'up');
    await sleep(1300);
  } finally {
    await send('Page.stopScreencast');
    await sleep(300);
    if (await overlayOpen()) { await key('back'); }
    ws.close();
  }

  // Frames only come when the screen changes: show each for as long as it was up
  const list = path.join(work, 'list.txt');
  fs.writeFileSync(list, frames.map(([n, t], i) => {
    const d = i + 1 < frames.length ? frames[i + 1][1] - t : 0.6;
    return `file '${path.join(work, n + '.jpg')}'\nduration ${d.toFixed(4)}\n`;
  }).join('') + `file '${path.join(work, frames[frames.length - 1][0] + '.jpg')}'\n`);
  const master = path.join(work, 'master.mp4');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-vf', 'fps=30,format=yuv420p',
    '-c:v', 'libx264', '-crf', '18', '-an', master]);
  const gif = path.join(ROOT, 'assets/app-tv.gif');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', master, '-vf',
    'fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle', gif]);
  console.log('wrote ' + path.relative(ROOT, gif));
  if (MP4) {
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', master, '-vf', 'scale=960:540:flags=lanczos', '-c:v', 'libx264',
      '-crf', '24', '-preset', 'slow', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', MP4]);
    console.log('wrote ' + MP4);
  }
  fs.rmSync(work, { recursive: true, force: true });
})().catch((e) => { console.error(e.message || e); process.exit(1); });
