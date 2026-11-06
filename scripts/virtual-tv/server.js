// Serves the TV app from the virtual TV (vtv.sh) at the same path it has on
// a real TV, with a stand-in for webOS's PalmServiceBridge.  The app's
// calls to the Homebrew Channel's exec service run on the virtual TV through
// vtv.sh exec; other Luna calls (like opening the Homebrew Channel) just
// answer returnValue true.  Only listens on 127.0.0.1.
//
//   node scripts/virtual-tv/server.js [PORT]      (default 8730)
//   then open http://127.0.0.1:8730/
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const VTV = path.join(__dirname, 'vtv.sh');
const DIR = process.env.VTV_DIR || path.join(require('os').homedir(), '.cache/lg-virtual-tv');
const APP = '/media/developer/apps/usr/palm/applications/org.ohmybahgosh.lgusb2eth0';
const APP_DIR = path.join(DIR, 'root', APP);
const PORT = Number(process.argv[2] || process.env.VTV_PORT || 8730);
const HBC_EXEC = 'luna://org.webosbrew.hbchannel.service/exec';

// The bridge, as webOS gives it to web apps: call(uri, json), and the reply
// arrives through onservicecallback(json)
const SHIM = `<script>
window.PalmServiceBridge = function () {};
window.PalmServiceBridge.prototype.call = function (uri, params) {
  var self = this;
  fetch('/luna', { method: 'POST', body: JSON.stringify({ uri: uri, params: JSON.parse(params || '{}') }) })
    .then(function (r) { return r.text(); })
    .then(function (t) { if (self.onservicecallback) { self.onservicecallback(t); } });
};
window.PalmSystem = { deviceInfo: '{"modelName":"virtual TV"}', platformBack: function () {} };
</script>`;

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.json': 'application/json', '.svg': 'image/svg+xml' };

function luna(body, res) {
  let req;
  try { req = JSON.parse(body); } catch (e) { req = {}; }
  const send = (o) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
  if (req.uri !== HBC_EXEC) { send({ returnValue: true }); return; }
  const cmd = String((req.params || {}).command || '');
  execFile(VTV, ['exec', cmd], { maxBuffer: 16 << 20, timeout: 120000 }, (err, stdout, stderr) => {
    // Paths as they are on a TV: without the virtual TV's folder
    const tv = (t) => String(t).split(path.join(DIR, 'root')).join('');
    send({ returnValue: true, exitCode: err ? (err.code || 1) : 0, stdoutString: tv(stdout), stderrString: tv(stderr) });
  });
}

http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/luna') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => luna(body, res));
    return;
  }
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/' || p === '/index.html') { res.writeHead(302, { location: APP + '/index.html' }); res.end(); return; }
  if (!p.startsWith(APP + '/')) { res.writeHead(404); res.end(); return; }
  const file = path.normalize(path.join(APP_DIR, p.slice(APP.length)));
  if (!file.startsWith(APP_DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  let data = fs.readFileSync(file);
  if (file.endsWith('index.html')) { data = Buffer.from(String(data).replace('<head>', '<head>' + SHIM)); }
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
  res.end(data);
}).listen(PORT, '127.0.0.1', () => console.log('Virtual TV app: http://127.0.0.1:' + PORT + '/'));
