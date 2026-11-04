// dev/wordmark.js — draws the README's wordmark as an SVG on stdout: the
// rows that `verbump --help` prints, each box-drawing cell as thick strokes,
// under the CLI's diagonal gradient (lib/styles.sh). dev/screenshots.sh turns
// it into img/wordmark-dark.png and img/wordmark-light.png with rsvg-convert.
// Pass `light` for the darker stops that read on a white page.
//
// Dev-only, like the rest of dev/: verbump.sh never needs Node.
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const script = path.join(__dirname, '..', 'verbump.sh');
const rows = process.env._VB_WORDMARK_ROWS
  ? process.env._VB_WORDMARK_ROWS.split('\n')
  : execFileSync(script, ['--help'], { env: { ...process.env, NO_COLOR: '1' }, encoding: 'utf8' })
  .split('\n')
  .slice(0, 3);

// The gradient's stops: WORDMARK_STOPS in lib/styles.sh, so the pictures
// match the CLI. _VB_WORDMARK_STOPS and _VB_WORDMARK_ROWS replace the stops
// and the rows, for the previews in docs/qa/wordmark-*/.
const fs = require('node:fs');
const styles = fs.readFileSync(path.join(__dirname, '..', 'lib', 'styles.sh'), 'utf8');
const hexes = (process.env._VB_WORDMARK_STOPS || styles.match(/^\s*WORDMARK_STOPS=\(([^)]*)\)/m)[1]).trim().split(/\s+/);

// A light page needs darker stops: the same hue, with the lightness capped
// at 42%, so even a yellow stop reads on white.
function darken(hex) {
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (l <= 0.42) return `#${hex}`;
  const d = max - min;
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  let h = 0;
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
  }
  h = (h + 6) % 6;
  const L = 0.42;
  const C = (1 - Math.abs(2 * L - 1)) * Math.min(1, s * 1.1);
  const X = C * (1 - Math.abs((h % 2) - 1));
  const m = L - C / 2;
  const [r1, g1, b1] = [[C, X, 0], [X, C, 0], [0, C, X], [0, X, C], [X, 0, C], [C, 0, X]][Math.floor(h)];
  return `#${[r1, g1, b1].map((v) => Math.round((v + m) * 255).toString(16).padStart(2, '0')).join('')}`;
}

const STOPS = { dark: hexes.map((h) => `#${h}`), light: hexes.map(darken) };
// WORDMARK_SHIFT in lib/styles.sh: each row starts the gradient 2 cells on.
const SHIFT = 2;

// Each glyph as the arms it draws from the cell's centre.
const ARMS = {
  '┏': 'rd', '┓': 'ld', '┗': 'ur', '┛': 'ul', '━': 'lr', '┃': 'ud',
  '┣': 'udr', '┫': 'udl', '┳': 'lrd', '┻': 'lru',
  '╸': 'l', '╺': 'r', '╹': 'u', '╻': 'd',
};

const W = 38.5;
const H = 63.5;
const STROKE = 14;
const PAD = 24;
const LEFT = PAD + W / 2;
const TOP = PAD + H / 2;
const half = STROKE / 2;
const cols = Math.max(...rows.map((row) => [...row].length));
const width = Math.ceil(cols * W + 2 * PAD);
const height = Math.ceil(rows.length * H + 2 * PAD);

// The pictures can do what a terminal cell grid cannot: the B's top bowl is
// 1.5 cells wide, not 1. Its right line (the B's ┓ and the ┻ under it) moves
// half a cell right. Vertical arms shift, and the horizontal arms stretch or
// shrink to meet them. The CLI keeps the 1-cell bowl.
const NUDGE = new Map();
const bCol = rows[1] ? rows[1].indexOf('┣┻┓') : -1;
if (bCol >= 0 && rows[0][bCol + 1] === '┓') {
  NUDGE.set(`${bCol + 1},0`, W / 2);
  NUDGE.set(`${bCol + 1},1`, W / 2);
}

// The R's leg steps in under its bowl. The CLI can only step a whole cell
// (┣┳┛ over ╹┗╸); the pictures step one stroke, so the leg's outer edge lines
// up with the bowl's inner edge. The leg's cells (the ┳ and the ┗ under it)
// move right, and the foot still ends at the bowl's outer edge.
const LEG = new Map();
const rCol = rows[1] ? rows[1].indexOf('┣┳┛') : -1;
if (rCol >= 0 && rows[2].slice(rCol, rCol + 3) === '╹┗╸') {
  const dx = W - STROKE;
  LEG.set(`${rCol + 1},1`, { d: ([x, y, w, h]) => [x + dx, y, w, h] });
  LEG.set(`${rCol + 1},2`, {
    u: ([x, y, w, h]) => [x + dx, y, w, h],
    r: ([x, y, w, h]) => [x + dx, y, w - dx, h],
  });
}

// The diagonals run corner to corner, as a terminal draws them.
const DIAGONALS = { '╲': [-1, -1, 1, 1], '╱': [1, -1, -1, 1] };

const rects = [];
rows.forEach((row, y) => {
  [...row].forEach((cell, x) => {
    const cx = LEFT + x * W;
    const cy = TOP + y * H;
    const diag = DIAGONALS[cell];
    if (diag) {
      const [x0, y0, x1, y1] = [cx + (diag[0] * W) / 2, cy + (diag[1] * H) / 2, cx + (diag[2] * W) / 2, cy + (diag[3] * H) / 2];
      const len = Math.hypot(x1 - x0, y1 - y0);
      const [nx, ny] = [(-(y1 - y0) / len) * half, ((x1 - x0) / len) * half];
      const pts = [[x0 + nx, y0 + ny], [x1 + nx, y1 + ny], [x1 - nx, y1 - ny], [x0 - nx, y0 - ny]];
      rects.push(`<polygon shape-rendering="geometricPrecision" points="${pts.map((p) => p.join(',')).join(' ')}"/>`);
    }
    const dx = NUDGE.get(`${x},${y}`) ?? 0;
    const leg = LEG.get(`${x},${y}`) ?? {};
    for (const arm of ARMS[cell] ?? '') {
      let r = {
        l: [cx - W / 2, cy - half, W / 2 + half + dx, STROKE],
        r: [cx - half + dx, cy - half, W / 2 + half - dx, STROKE],
        u: [cx - half + dx, cy - H / 2, STROKE, H / 2 + half],
        d: [cx - half + dx, cy - half, STROKE, H / 2 + half],
      }[arm];
      if (leg[arm]) r = leg[arm](r);
      rects.push(`<rect x="${r[0]}" y="${r[1]}" width="${r[2]}" height="${r[3]}"/>`);
    }
  });
});

// The gradient runs from the first cell's centre, across the direction in
// which a cell's place in it, (x + SHIFT * y) / span, grows.
const span = cols - 1 + SHIFT * (rows.length - 1);
const [gx, gy] = [1 / W, SHIFT / H];
const s = span / (gx * gx + gy * gy);
const stops = STOPS[process.argv[2] === 'light' ? 'light' : 'dark'];

process.stdout.write(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="${LEFT}" y1="${TOP}" x2="${LEFT + s * gx}" y2="${TOP + s * gy}">
${stops.map((c, i) => `<stop offset="${i / (stops.length - 1)}" stop-color="${c}"/>`).join('\n')}
</linearGradient></defs>
<g fill="url(#g)" shape-rendering="crispEdges">
${rects.join('\n')}
</g>
</svg>
`);
