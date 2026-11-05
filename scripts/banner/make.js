// Render the README banner (assets/banner.webp) from banner.html, which uses
// the app icon and the status screenshot (assets/screenshots/app-home.png).
// Run scripts/screenshots/take.js first if the app changed.
// Needs Playwright (npm i playwright) and ffmpeg.  Usage: node scripts/banner/make.js
'use strict';
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'assets/banner.webp');

(async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lgu2e-banner-'));
  const raw = path.join(tmp, 'banner@2x.png');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 800 }, deviceScaleFactor: 2 });
  await page.goto('file://' + path.join(__dirname, 'banner.html'));
  await page.waitForTimeout(500);
  await page.screenshot({ path: raw });
  await browser.close();
  // Rendered at 2x for sharp text, then scaled down to 1600x800
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', raw, '-vf', 'scale=1600:800:flags=lanczos',
    '-c:v', 'libwebp', '-quality', '90', OUT]);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('wrote ' + path.relative(ROOT, OUT));
})();
