// Takes the TV app screenshots and the demo GIF in assets/, from the built
// app (webos-app/dist) with made-up data (demo.js).  Needs Playwright
// (npm i playwright) and ffmpeg; pngquant is used if it's there.  With
// --mp4 FILE it also writes the demo as an MP4 (for web pages, where a
// video is much smaller than the GIF).
//
//   sh webos-app/build.sh && node scripts/screenshots/take.js [--mp4 FILE]
'use strict';
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const DIST = path.join(ROOT, 'webos-app/dist');
const OUT = path.join(ROOT, 'assets/screenshots');
const mp4Arg = process.argv.indexOf('--mp4');
const MP4 = mp4Arg > 0 ? path.resolve(process.argv[mp4Arg + 1]) : '';
const has = (cmd) => { try { execFileSync('sh', ['-c', 'command -v ' + cmd], { stdio: 'ignore' }); return true; } catch (e) { return false; } };

if (!fs.existsSync(path.join(DIST, 'index.html'))) { console.error('Build the app first: sh webos-app/build.sh'); process.exit(1); }
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'lgu2e-shots-'));
fs.cpSync(DIST, path.join(work, 'app'), { recursive: true });
fs.copyFileSync(path.join(__dirname, 'demo.js'), path.join(work, 'app/demo.js'));
const index = path.join(work, 'app/index.html');
fs.writeFileSync(index, fs.readFileSync(index, 'utf8').replace('<script src="app.js">', '<script src="demo.js"></script>\n<script src="app.js">'));
const url = 'file://' + index;
fs.mkdirSync(OUT, { recursive: true });

// 1600x900 PNGs, quantized to keep the repository small
function savePng(raw, name) {
  const dest = path.join(OUT, name);
  const small = path.join(work, 'small-' + name);
  if (has('pngquant')) {
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', raw, '-vf', 'scale=1600:-1:flags=lanczos', small]);
    execFileSync('pngquant', ['--quality=80-95', '--speed', '1', '--force', '--output', dest, small]);
  } else {
    // ffmpeg can make a 256-colour PNG on its own
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', raw, '-vf',
      'scale=1600:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a', dest]);
  }
  console.log('wrote ' + path.relative(ROOT, dest));
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  const shot = async (query, name, before) => {
    await page.goto(url + query);
    await page.waitForTimeout(600);
    if (before) { await before(); }
    const raw = path.join(work, 'raw-' + name);
    await page.screenshot({ path: raw });
    savePng(raw, name);
  };
  const click = (action, wait) => async () => {
    await page.evaluate((a) => document.querySelector('[data-action="' + a + '"]').click(), action);
    await page.waitForTimeout(wait);
  };
  await shot('?x=1', 'app-home.png');
  await shot('?ver=2.3.2', 'app-update.png', async () => {
    await page.evaluate(() => document.querySelector('[data-action="update"]').focus());
  });
  await shot('?sd=50', 'app-speed.png', click('speed', 800));
  await shot('?x=1', 'app-report.png', click('report', 500));
  await browser.close();

  // The GIF: move down to Speed test, run it, close it, open the report
  const vctx = await (await chromium.launch()).newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: { dir: path.join(work, 'vid'), size: { width: 1920, height: 1080 } }
  });
  const v = await vctx.newPage();
  const w = (ms) => v.waitForTimeout(ms);
  await v.goto(url + '?speed=0&sd=1500');
  await w(2200);
  for (let i = 0; i < 4; i++) { await v.keyboard.press('ArrowDown'); await w(450); }
  await w(500); await v.keyboard.press('Enter');
  await w(7800);
  await v.keyboard.press('Enter'); await w(900);
  await v.keyboard.press('ArrowDown'); await w(700);
  await v.keyboard.press('Enter'); await w(3200);
  await v.keyboard.press('Enter'); await w(800);
  const video = await v.video().path();
  await vctx.close();
  await vctx.browser().close();
  const gif = path.join(ROOT, 'assets/app-demo.gif');
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-ss', '0.6', '-i', video, '-vf',
    'fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle', gif]);
  console.log('wrote ' + path.relative(ROOT, gif));
  if (MP4) {
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-ss', '0.6', '-i', video, '-vf', 'fps=12,scale=960:-2:flags=lanczos',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '24', '-preset', 'slow', '-movflags', '+faststart', '-an', MP4]);
    console.log('wrote ' + MP4);
  }
  fs.rmSync(work, { recursive: true, force: true });
})().catch((e) => { console.error(e); process.exit(1); });
