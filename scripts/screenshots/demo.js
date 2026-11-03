// Made-up answers from the script, so the TV app runs in a desktop browser
// for the README screenshots (see take.js).  No real addresses: the IP is a
// documentation-style private one and the MACs are masked like 'report' does.
// URL options: ?ver=2.3.1 shows the update row, ?speed=0 hides the last
// speed test, ?sd=MS sets how long each speed test phase takes.
(function () {
  var p = new URLSearchParams(location.search);
  var ver = p.get('ver') || '2.3.2';
  var withSpeed = p.get('speed') !== '0';
  var status = {
    version: ver, model: 'OLED65C2PUA', webos: 'webOS 25', webosRelease: '10.3.1', firmware: '33.30.65', kernel: '5.4.268-329.ptl4tv.5',
    hook: { state: 'enabled', link: '', wait: '120', mac: '', module: '/home/root/lg-usb-2-eth0/r8152_oot.ko', driver: 'r8152_oot', watch: true, wifiFallback: true, wifiFallbackOn: false, running: true, pid: '1234' },
    adapter: { name: 'eth0', driver: 'r8152_oot', mac: '', carrier: true, speed: 1000, duplex: 'full', ip: '192.168.1.42/24', id: '0bda:8156', chip: 'Realtek RTL8156', bus: 'USB 2.0' },
    adapterIsEth0: true,
    builtin: { name: 'eth2', driver: 'lg1k_eth', mac: '', carrier: false, speed: 0, ip: '' },
    wifi: { name: 'wlan0', driver: 'mtk', mac: '', carrier: false, speed: 0, ip: '' },
    defaultRoute: 'eth0', knownDriver: true, driverOffer: 'active', driverFile: '/home/root/lg-usb-2-eth0/r8152_oot.ko', driverDownloaded: true, autobindHook: false,
    speed: withSpeed ? { interface: 'eth0', server: 'DTW', pingMs: 7, downMbps: 272, upMbps: 287, at: 0 } : null,
    issues: [], notes: [],
    log: ['=== boot hook (wait 120s, module /home/root/lg-usb-2-eth0/r8152_oot.ko) ===', 'Done: the USB adapter is eth0, the built-in port is eth2.']
  };
  var report = ['```', 'LG-USB-2-ETH0 v' + ver + ' report', 'Model:   OLED65C2PUA', 'webOS:   webOS 25 (10.3.1), firmware 33.30.65',
    'Kernel:  5.4.268-329.ptl4tv.5 (armv7l)', 'Hook:    enabled, wait 120s, module r8152_oot.ko, watch, wifi-fallback', 'Interfaces:',
    '  eth0 usb driver=r8152_oot mac=00:e0:4c:xx:xx:xx carrier=1 link=1000M id=0bda:8156 bus=USB 2.0',
    '  eth2 builtin driver=lg1k_eth mac=a8:23:fe:xx:xx:xx carrier=0',
    '  wlan0 wifi driver=mtk mac=a8:23:fe:xx:xx:xx carrier=0',
    'Drivers loaded: r8152_oot cdc_ncm usbnet', 'Default route: eth0', 'Speed:   272 down / 287 up Mbit/s, 7 ms, over eth0 (speedtest)', '```'].join('\n');
  var speedDelay = +(p.get('sd') || 1400);
  window.LGU2E_DEMO = function (args, cb) {
    var out = '', d = 120;
    if (/^status/.test(args)) { out = JSON.stringify(status); }
    else if (/^update --check/.test(args)) {
      out = JSON.stringify(ver === '2.3.2' ? { current: ver, latest: '2.3.2', newer: false, kind: 'app', source: 'github' }
                                            : { current: ver, latest: '2.3.2', newer: true, kind: 'app', source: 'github' });
    }
    else if (/--phase ping/.test(args)) { out = JSON.stringify({ interface: 'eth0', server: 'DTW', pingMs: 7 }); d = speedDelay * 0.6; }
    else if (/--phase down/.test(args)) { out = JSON.stringify({ downMbps: 272 }); d = speedDelay; }
    else if (/--phase up/.test(args)) { out = JSON.stringify({ upMbps: 287 }); d = speedDelay; }
    else if (/^report/.test(args)) { out = report; }
    setTimeout(function () { cb(true, out, ''); }, d);
  };
}());
