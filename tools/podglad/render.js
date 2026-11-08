// Renderuje podglądy PNG modelu (three.js + Playwright).
// Użycie (z katalogu tools/podglad, po `npm install three@0.160.0`):
//   python3 -m http.server 8765 &   # serwuje ten katalog
//   node render.js widoki.json
// widoki.json: [{"q": {...parametry index.html...}, "out": "plik.png"}, ...]
const { chromium } = require('playwright');
const fs = require('fs');
const views = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 2 });
  p.on('pageerror', (e) => console.log('pageerror', e.message));
  for (const v of views) {
    await p.goto('http://localhost:8765/index.html?' + new URLSearchParams(v.q).toString());
    await p.waitForFunction(() => document.title === 'done', null, { timeout: 180000 });
    await p.screenshot({ path: v.out });
    console.log('zapisano', v.out);
  }
  await b.close();
})();
