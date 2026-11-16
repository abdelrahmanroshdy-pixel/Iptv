const { chromium } = require('playwright');
const path = require('path'); const fs = require('fs');
const [,, mode, outDir, ...times] = process.argv;
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.resolve(__dirname, 'ep1/index.html'));
  await page.evaluate(() => window.ready);
  fs.mkdirSync(outDir, { recursive: true });
  let list;
  if (mode === 'all') { const fps = 30, dur = await page.evaluate(() => T.end); list = []; for (let i = 0; i < Math.round(dur * fps); i++) list.push(i / fps); }
  else list = times.map(Number);
  for (let i = 0; i < list.length; i++) {
    await page.evaluate(t => render(t), list[i]);
    const name = mode === 'all' ? `f${String(i).padStart(4, '0')}.png` : `t${list[i].toFixed(2)}.png`;
    await page.screenshot({ path: path.join(outDir, name) });
  }
  await browser.close();
})();
