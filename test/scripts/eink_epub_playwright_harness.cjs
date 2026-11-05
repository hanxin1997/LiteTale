// Runs the production color function against Chromium's actual CSS cascade.
// Uses the already installed runtime; does not download browsers or packages.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH ||
  'C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

(async () => {
  const source = fs.readFileSync(path.resolve(__dirname, '../../lib/assets/epub_page_engine.js'), 'utf8');
  const start = source.indexOf('      const applyEink = doc => {');
  const end = source.indexOf('      const applyStyle = doc => {', start);
  assert(start >= 0 && end > start);
  const functionSource = source.slice(start, end) + '; return applyEink;';
  const browser = await chromium.launch({
    executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH ||
      'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
  });
  try {
    const page = await browser.newPage({viewport: {width: 600, height: 800}});
    const markup = `<!doctype html><style>
      body { margin: 12px; color: rgb(30,60,90); background: #132435; }
      p { width: 260px; font: 19px/1.6 serif; padding: 9px; border: 2px solid #ddd; }
      svg, :is(p, article)::first-letter { color: #ccc; -webkit-text-fill-color: #ccc; background: #222; }
      @media (min-width: 9000px) { td::first-letter { color: #abc; } }
      @supports (not (display: grid)) { td::first-line { color: #def; } }
      td { border: 1px solid #ccc; background: #333; }
    </style>
    <p id="text" style="color:#ddd!important;background-color:#222!important">A publisher paragraph with important colors, long enough to wrap without changing its geometry.</p>
    <table><tr><td id="cell">Table text</td></tr></table>
    <svg id="art" width="80" height="60" viewBox="0 0 80 60">
      <rect id="shape" width="80" height="60" fill="currentColor"/>
      <text x="0" y="20">Artwork</text>
    </svg>
    <img id="bitmap" width="20" height="20" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'%3E%3Crect width='20' height='20' fill='red'/%3E%3C/svg%3E">`;
    const inspect = () => {
      const read = id => {
        const el = document.getElementById(id), css = getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return {color:css.color,background:css.backgroundColor,border:css.borderColor,
          fill:css.fill,stroke:css.stroke,font:css.font,lineHeight:css.lineHeight,
          width:rect.width,height:rect.height,src:el.getAttribute('src')};
      };
      const result = Object.fromEntries(['text','cell','art','shape','bitmap'].map(id=>[id,read(id)]));
      const first = getComputedStyle(document.getElementById('text'), '::first-letter');
      result.firstLetter = {color:first.color,fill:first.webkitTextFillColor,background:first.backgroundColor};
      result.styleCount = document.styleSheets.length;
      return result;
    };
    const settle = () => page.evaluate(async () => {
      await document.fonts.ready;
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    });
    for (const options of [{}, {eink:false}, {eink:true,fixed:true}, {eink:true,fixed:false}]) {
      await page.setContent(markup);
      await settle();
      const before = await page.evaluate(inspect);
      await page.evaluate(({functionSource,options}) => {
        new Function('options', functionSource)(options)(document);
      }, {functionSource,options});
      await settle();
      const after = await page.evaluate(inspect);
      if (!options.eink || options.fixed) {
        assert.deepEqual(after, before);
      } else {
        for (const id of ['text','cell']) {
          assert.equal(after[id].color, 'rgb(0, 0, 0)');
          assert.equal(after[id].background, 'rgb(255, 255, 255)');
          assert.equal(after[id].border, 'rgb(0, 0, 0)');
          for (const metric of ['font','lineHeight','width','height']) {
            assert.equal(after[id][metric], before[id][metric], `${id}.${metric}`);
          }
        }
        assert.equal(after.firstLetter.color, 'rgb(0, 0, 0)');
        assert.equal(after.firstLetter.fill, 'rgb(0, 0, 0)');
        assert.equal(after.firstLetter.background, 'rgb(255, 255, 255)');
        assert.deepEqual(after.art, before.art);
        assert.deepEqual(after.shape, before.shape);
        // Image content and dimensions survive; surrounding text ink is allowed
        // to inherit into the inert HTML img element without modifying pixels.
        for (const metric of ['src','width','height']) {
          assert.equal(after.bitmap[metric], before.bitmap[metric]);
        }
        await page.evaluate(({functionSource,options}) => {
          new Function('options', functionSource)(options)(document);
        }, {functionSource,options});
        await settle();
        assert.deepEqual(await page.evaluate(inspect), after,
          'Repeated load events must not grow styles or recolor artwork');
      }
    }
    console.log('Chromium EPUB colors, inline priority, metrics, SVG and fixed-layout checks passed');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error);process.exitCode = 1;});
