/* LifeTwin web art. Dependency-free port of the Flutter painters:
 *   lt_twin.dart, lt_mascot.dart, lt_magic_ball.dart, lt_habitat.dart,
 *   lt_game_health_meter.dart, lt_icon.dart.
 * Every function returns an SVG markup string. Colours come from tokens.css
 * custom properties (brand + scene) or, for the twin's skin/hair/cheek, from
 * the lt_cosmetics palettes below. Pair with art.css for the animations.
 *
 * Sizing: the <svg> has a viewBox and no width/height, so size it from CSS
 * (e.g. `width: 120px` or `width: 100%; height: auto`). Nothing is clipped by
 * the svg, the viewBox carries a margin for sprouts, arms and sparkles.
 */

// ---- cosmetics (lt_cosmetics.dart) -------------------------------------
const SKIN = ['#F6D7C3', '#E8B894', '#C98E64', '#8D5A3B', '#5A3825'];
const HAIR = {
  black: '#2B1B12',
  brown: '#5B3A24',
  auburn: '#A0522D',
  blonde: '#D9B26F',
  silver: '#B8BCC6',
};
const CHEEK = '#F5A3A3';
const INK = 'var(--ink)'; // char/line
const SHINE = 'var(--surface)'; // char/eye-shine (white)
const TOPS = { blue: '--blue-600', green: '--green-600', sun: '--sun', sky: '--blue-400', slate: '--baseline' };

// ---- helpers -----------------------------------------------------------
let seq = 0;
const uid = (p) => `lt-${p}${++seq}`;
const n = (v) => +v.toFixed(2);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const v = (token) => `var(${token})`;
const mix = (a, pct, b) => `color-mix(in srgb, ${a} ${pct}%, ${b})`;

function open(viewBox, cls, title, extra = '') {
  const id = uid('t');
  const a11y = title ? `role="img" aria-labelledby="${id}"` : 'aria-hidden="true" focusable="false"';
  const t = title ? `<title id="${id}">${esc(title)}</title>` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" class="lt-svg ${cls}" ${a11y}${extra ? ' ' + extra : ''}>${t}`;
}

const star = (x, y, r, attrs = '') =>
  `<path ${attrs} d="M${n(x)} ${n(y - r)}Q${n(x)} ${n(y)} ${n(x + r)} ${n(y)}Q${n(x)} ${n(y)} ${n(x)} ${n(y + r)}Q${n(x)} ${n(y)} ${n(x - r)} ${n(y)}Q${n(x)} ${n(y)} ${n(x)} ${n(y - r)}Z"/>`;

// Flutter drawArc: angles clockwise from +x, y down.
function arc(cx, cy, rx, ry, a0, sweep) {
  const x0 = cx + rx * Math.cos(a0), y0 = cy + ry * Math.sin(a0);
  const x1 = cx + rx * Math.cos(a0 + sweep), y1 = cy + ry * Math.sin(a0 + sweep);
  return `M${n(x0)} ${n(y0)}A${rx} ${ry} 0 ${Math.abs(sweep) > Math.PI ? 1 : 0} ${sweep > 0 ? 1 : 0} ${n(x1)} ${n(y1)}`;
}

// Flutter RRect.fromRectAndCorners, including its radius down-scaling.
function rrect(x, y, w, h, tl, tr, br, bl) {
  const k = Math.min(1, w / (tl + tr), w / (bl + br), h / (tl + bl), h / (tr + br));
  [tl, tr, br, bl] = [tl, tr, br, bl].map((r) => r * k);
  return `M${n(x + tl)} ${y}H${n(x + w - tr)}A${n(tr)} ${n(tr)} 0 0 1 ${x + w} ${n(y + tr)}V${n(y + h - br)}` +
    `A${n(br)} ${n(br)} 0 0 1 ${n(x + w - br)} ${y + h}H${n(x + bl)}A${n(bl)} ${n(bl)} 0 0 1 ${x} ${n(y + h - bl)}` +
    `V${n(y + tl)}A${n(tl)} ${n(tl)} 0 0 1 ${n(x + tl)} ${y}Z`;
}

function topColor(top) {
  const t = String(top ?? 'blue');
  if (TOPS[t.toLowerCase()]) return v(TOPS[t.toLowerCase()]);
  return v(t.startsWith('--') ? t : `--${t}`); // any brand token, e.g. 'green-400'
}

// ---- Twin (lt_twin.dart) -----------------------------------------------
// Design box is 120 x 150; the viewBox adds room for the sprout, raised arms
// and sparkles. Feet sit at y=146. Body shape is fixed (never data-driven).
const TWIN_VB = '-12 -22 144 172';
const TWIN_FOOT = (146 + 22) / 172;

const POSES = {
  rest: [[20, 134], [100, 134]],
  wave: [[20, 134], [110, 78]],
  cheer: [[10, 80], [110, 80]],
  huddle: [[34, 132], [86, 132]],
  reach: [[20, 134], [118, 104]],
};

function twinArms(top, skin, pose) {
  const [lh, rh] = POSES[pose] || POSES.rest;
  return [[34, 108, lh], [86, 108, rh]]
    .map(([fx, fy, [tx, ty]]) => {
      const mx = (fx + tx) / 2, my = (fy + ty) / 2 + (ty < fy ? 4 : -2);
      return `<path d="M${fx} ${fy}Q${n(mx)} ${n(my)} ${tx} ${ty}" fill="none" stroke="${top}" stroke-width="13" stroke-linecap="round"/>` +
        `<circle cx="${tx}" cy="${ty}" r="7" fill="${skin}"/>`;
    })
    .join('');
}

function twinHairBack(style, hair) {
  if (style === 'bob') return `<path d="${rrect(7, 30, 106, 66, 53, 53, 22, 22)}" fill="${hair}"/>`;
  if (style === 'curly') {
    return [150, 180, 210, 240, 270, 300, 330, 360, 30]
      .map((a) => {
        const r = (a * Math.PI) / 180;
        return `<circle cx="${n(60 + Math.cos(r) * 46)}" cy="${n(52 + Math.sin(r) * 46)}" r="13" fill="${hair}"/>`;
      })
      .join('');
  }
  return '';
}

function twinHairFront(style, hair) {
  if (style === 'bob') {
    return `<path fill="${hair}" d="M10 56Q8 2 60 2Q112 2 110 56Q98 24 60 26Q22 24 10 56Z"/>`;
  }
  if (style === 'curly') {
    return [30, 45, 60, 75, 90]
      .map((x) => `<circle cx="${x}" cy="${n(14 + Math.abs(x - 60) * 0.18)}" r="12" fill="${hair}"/>`)
      .join('');
  }
  return `<path fill="${hair}" d="M12 50Q10 4 60 3Q110 4 108 50Q90 26 60 28Q30 26 12 50Z"/>`;
}

const dotEye = (x, y) =>
  `<circle cx="${x}" cy="${y}" r="4" fill="${INK}"/><circle cx="${n(x - 1.3)}" cy="${n(y - 1.4)}" r="1.4" fill="${SHINE}"/>`;

function twinFace(mood) {
  const sk = `fill="none" stroke="${INK}" stroke-width="3.5" stroke-linecap="round"`;
  const L = [44, 54], R = [76, 54];
  let eyes;
  switch (mood) {
    case 'calm':
      eyes = [L, R].map(([x, y]) => `<path ${sk} d="${arc(x, y, 6, 4, 0.2, Math.PI - 0.4)}"/>`).join('');
      break;
    case 'tired':
      eyes = [L, R].map(([x, y]) => `<path ${sk} d="M${x - 6} ${y}L${x + 6} ${y + 1}"/>`).join('');
      break;
    case 'thinking':
      eyes = dotEye(L[0] + 2, L[1] - 3) + dotEye(R[0] + 2, R[1] - 3);
      break;
    case 'sick':
      eyes = [L, R].map(([x, y]) => `<path ${sk} d="${arc(x, y, 6, 4, Math.PI + 0.3, Math.PI - 0.6)}"/>`).join('');
      break;
    default: // happy, recovering
      eyes = dotEye(...L) + dotEye(...R);
  }
  const mouth = {
    happy: 'M46 74Q60 88 74 74',
    recovering: 'M48 75Q60 84 72 75',
    calm: 'M50 76Q60 81 70 76',
    tired: 'M52 78L68 78',
    thinking: 'M52 78Q60 74 68 79',
    sick: 'M50 80Q60 73 70 80',
  }[mood];
  return `<g class="lt-blink">${eyes}</g><path ${sk} d="${mouth}"/>`;
}

function twinMoodExtras(mood) {
  const stem = (d) => `<path d="${d}" fill="none" stroke="var(--green-600)" stroke-width="3" stroke-linecap="round"/>`;
  const leaf = (x, y) => `<ellipse cx="${x}" cy="${y}" rx="6.5" ry="4" fill="var(--green-600)"/>`;
  const sway = 'style="transform-origin:60px 4px"';
  if (mood === 'sick') {
    return `<g class="lt-sprout lt-droop" ${sway}>${stem('M60 4Q60 -6 70 -4')}${leaf(75, 0)}</g>` +
      `<g class="lt-sniffle"><line x1="70" y1="78" x2="98" y2="68" stroke="var(--surface)" stroke-width="5" stroke-linecap="round"/>` +
      `<circle cx="70" cy="78" r="4" fill="var(--blue-600)"/></g>`;
  }
  if (mood === 'recovering') {
    return `<g class="lt-sprout" ${sway}>${stem('M60 4Q60 -8 66 -10')}${leaf(70, -10)}</g>` +
      `<g class="lt-sparkle" style="transform-origin:100px 20px" fill="var(--sun)">${star(100, 20, 5)}</g>` +
      `<g class="lt-sparkle lt-late" style="transform-origin:14px 30px" fill="var(--sun)">${star(14, 30, 4)}</g>`;
  }
  if (mood === 'thinking') {
    return `<circle class="lt-think" cx="106" cy="20" r="3" fill="var(--blue-400)"/>` +
      `<circle class="lt-think lt-late" cx="112" cy="8" r="4.5" fill="var(--blue-400)"/>`;
  }
  return '';
}

export function twinSVG({ mood = 'happy', skin = 1, hair = 'short', hairColor = 'black', top = 'blue', extra = 'none', pose = 'rest', title } = {}) {
  const skinC = SKIN[Math.min(5, Math.max(1, skin)) - 1];
  const hairC = HAIR[hairColor] || HAIR.black;
  const hs = hair === 'short' ? 'short' : hair; // 'short' | 'bob' | 'curly'
  const t = topColor(top);
  const cheek = `fill="${CHEEK}" fill-opacity="0.55"`;
  const glasses = extra === 'glasses'
    ? `<g fill="none" stroke="${INK}" stroke-width="2.5"><circle cx="44" cy="54" r="11"/><circle cx="76" cy="54" r="11"/><path d="M55 54H65" stroke-linecap="round"/></g>`
    : '';
  const headband = extra === 'headband'
    ? `<rect x="11" y="24" width="98" height="9" rx="5" fill="var(--blue-600)"/>`
    : '';
  // Sick is a playful sniffle: a green hint mixed into the skin itself, so every
  // skin depth keeps its own tone instead of a pale overlay.
  const face = mood === 'sick' ? `color-mix(in srgb, ${skinC} 80%, var(--green-400))` : skinC;
  return open(TWIN_VB, `lt-twin lt-mood-${mood}`, title, `data-foot="${n(TWIN_FOOT)}"`) +
    `<g class="lt-bob">` +
    twinArms(t, skinC, pose) +
    `<path d="${rrect(24, 96, 72, 50, 30, 30, 20, 20)}" fill="${t}"/>` +
    `<rect x="50" y="90" width="20" height="14" rx="8" fill="${skinC}"/>` +
    twinHairBack(hs, hairC) +
    `<circle cx="60" cy="52" r="50" style="fill:${face}"/>` +
    twinHairFront(hs, hairC) + headband +
    `<circle cx="36" cy="66" r="7" ${cheek}/><circle cx="84" cy="66" r="7" ${cheek}/>` +
    twinFace(mood) + glasses + twinMoodExtras(mood) +
    `</g></svg>`;
}

// ---- Pip (lt_mascot.dart) ----------------------------------------------
// Design box 100 x 110; orb centre (50,62) r38, bottom at y=100.
const PIP_VB = '-4 -2 108 116';
const PIP_FOOT = (100 + 2) / 116;

export function pipSVG({ state = 'idle', shadow = false, title } = {}) {
  const g = uid('pip');
  const fill = `fill="${INK}"`;
  const sk = `fill="none" stroke="${INK}" stroke-width="3" stroke-linecap="round"`;
  const L = [38, 62], R = [62, 62];
  const dot = (p, r, dx = 0, dy = 0) => `<circle cx="${p[0] + dx}" cy="${p[1] + dy}" r="${r}" ${fill}/>`;
  let eyes, mouth, extras = '';
  switch (state) {
    case 'listening':
      eyes = dot(L, 5.5) + dot(R, 5.5);
      break;
    case 'thinking':
      eyes = dot(L, 4, 2, -3) + dot(R, 4, 2, -3);
      break;
    case 'celebrating':
      eyes = [L, R].map(([x, y]) => `<path ${sk} d="${arc(x, y, 6, 4.5, Math.PI + 0.3, Math.PI - 0.6)}"/>`).join('');
      break;
    default:
      eyes = dot(L, 4) + dot(R, 4);
  }
  switch (state) {
    case 'speaking': mouth = `<ellipse class="lt-talk" cx="50" cy="76" rx="6" ry="5" ${fill}/>`; break;
    case 'celebrating': mouth = `<path ${sk} d="M40 72Q50 86 60 72"/>`; break;
    case 'thinking': mouth = `<path ${sk} d="M45 76L55 75"/>`; break;
    default: mouth = `<path ${sk} d="M43 74Q50 80 57 74"/>`;
  }
  if (state === 'listening') {
    const ring = `fill="none" stroke="var(--blue-600)" stroke-width="2.5" stroke-linecap="round"`;
    extras = `<path class="lt-ring" ${ring} d="${arc(50, 62, 46, 46, -0.5, 1)}"/><path class="lt-ring lt-late" ${ring} d="${arc(50, 62, 46, 46, Math.PI - 0.5, 1)}"/>`;
  } else if (state === 'thinking') {
    extras = `<circle class="lt-think" cx="88" cy="24" r="2.5" fill="var(--blue-400)"/><circle class="lt-think lt-late" cx="94" cy="12" r="4" fill="var(--blue-400)"/>`;
  } else if (state === 'celebrating') {
    extras = [[14, 28, ''], [88, 34, ' lt-late'], [92, 80, ' lt-later']]
      .map(([x, y, c]) => `<g class="lt-sparkle${c}" style="transform-origin:${x}px ${y}px" fill="var(--sun)">${star(x, y, 6)}</g>`)
      .join('');
  }
  const shade = shadow
    ? `<defs><filter id="${g}-b" x="-30%" y="-200%" width="160%" height="500%"><feGaussianBlur stdDeviation="3"/></filter></defs>` +
      `<ellipse cx="50" cy="104" rx="30" ry="4" fill="var(--ink)" fill-opacity="0.10" filter="url(#${g}-b)"/>`
    : '';
  return open(PIP_VB, `lt-pip lt-state-${state}`, title, `data-foot="${n(PIP_FOOT)}"`) +
    `<defs><linearGradient id="${g}-o" gradientUnits="userSpaceOnUse" x1="12" y1="24" x2="88" y2="100">` +
    `<stop offset="0" stop-color="var(--blue-400)"/><stop offset="1" stop-color="var(--green-400)"/></linearGradient></defs>` +
    shade +
    `<g class="lt-bob">` +
    `<g class="lt-sprout" style="transform-origin:50px 26px">` +
    `<path d="M50 26Q50 12 56 8" fill="none" stroke="var(--green-600)" stroke-width="3.5" stroke-linecap="round"/>` +
    `<path d="M56 8Q70 2 76 12Q64 20 56 8Z" fill="var(--green-600)"/>` +
    `<path d="M52 14Q40 6 32 12Q42 22 52 14Z" fill="var(--green-400)"/></g>` +
    `<circle cx="50" cy="62" r="38" fill="url(#${g}-o)"/>` +
    `<ellipse cx="36" cy="44" rx="7" ry="4.5" fill="var(--surface)" fill-opacity="0.55"/>` +
    eyes + mouth + extras +
    `</g></svg>`;
}

// ---- Magic ball (lt_magic_ball.dart) -----------------------------------
// Design box w x 1.15w with w=100. glow 0..1 is the "revealed" amount.
export function magicBallSVG({ glow = 0, title } = {}) {
  const t = Math.min(1, Math.max(0, glow));
  const g = uid('ball');
  const core = mix('var(--blue-400)', n(t * 55), 'var(--blue-100)'); // lerp(blue-100, blue-400, t*.55)
  const spots = [[50, 42, 9], [64, 56, 6], [38, 60, 5]];
  const sparkles = t > 0
    ? spots.map(([x, y, s], i) =>
        `<g class="lt-sparkle${i ? (i > 1 ? ' lt-later' : ' lt-late') : ''}" style="transform-origin:${x}px ${y}px" fill="var(--sun)">${star(x, y, n(s * t))}</g>`).join('')
    : '';
  return open('-3 -3 106 121', 'lt-ball', title, `style="--glow:${n(t)}"`) +
    `<defs><radialGradient id="${g}-s" gradientUnits="userSpaceOnUse" cx="41.2" cy="41.2" r="44">` +
    `<stop offset="0" style="stop-color:${core}"/><stop offset="0.62" stop-color="var(--blue-100)"/><stop offset="1" stop-color="var(--surface)"/></radialGradient></defs>` +
    `<g class="lt-bob">` +
    `<path d="M28 115H72L64 86H36Z" fill="var(--lavender-100)" stroke="var(--baseline)" stroke-width="2" stroke-linejoin="round"/>` +
    `<circle cx="50" cy="50" r="44" fill="url(#${g}-s)"/>` +
    `<circle class="lt-glow" cx="50" cy="50" r="44" fill="var(--blue-400)" fill-opacity="0"/>` +
    `<circle cx="50" cy="50" r="44" fill="none" stroke="var(--blue-400)" stroke-width="2.5"/>` +
    `<path d="${arc(50, 50, 31.68, 31.68, Math.PI * 1.1, Math.PI * 0.35)}" fill="none" stroke="var(--surface)" stroke-width="4" stroke-linecap="round"/>` +
    sparkles +
    `</g></svg>`;
}

// ---- Habitat (lt_habitat.dart) -----------------------------------------
// Scene colours are the --scene-* custom properties of tokens.css; the svg
// carries its own `tier-*` class so they resolve per instance and can crossfade.
const ASPECTS = {
  room: { w: 400, h: 500, fadeTop: 90, fadeBottom: 120 },
  wide: { w: 960, h: 420, fadeTop: 70, fadeBottom: 110 },
};
const sc = (name) => `var(--scene-${name})`;

function mulberry(seed) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function bush(cx, cy, r, i) {
  const blobs = [[-r * 0.7, -r * 0.55, r * 0.62], [0, -r * 0.85, r * 0.78], [r * 0.75, -r * 0.5, r * 0.58]];
  const shade = blobs.map(([dx, dy, rr]) =>
    `<circle cx="${n(cx + dx + rr * 0.16)}" cy="${n(cy + dy + rr * 0.14)}" r="${n(rr)}" style="fill:${sc('foliage-deep')};fill-opacity:.55"/>`).join('');
  const body = blobs.map(([dx, dy, rr]) =>
    `<circle cx="${n(cx + dx)}" cy="${n(cy + dy)}" r="${n(rr)}" style="fill:${sc('foliage')}"/>`).join('');
  const lit = `<circle cx="${n(cx - r * 0.22)}" cy="${n(cy - r * 1.12)}" r="${n(r * 0.22)}" style="fill:${mix(sc('light'), 45, sc('foliage'))};fill-opacity:.7"/>`;
  return `<g class="bleed-bush-${i}">${shade}${body}${lit}</g>`;
}

function tuft(bx, by, r) {
  const blades = [[-0.6, 0.9, -0.35], [-0.15, 1.3, -0.1], [0.3, 1.05, 0.25], [0.7, 0.7, 0.4]]
    .map(([dx, hg, lean]) => {
      const x = bx + dx * r;
      return `M${n(x - r * 0.14)} ${by}Q${n(x + lean * r * 0.4)} ${n(by - hg * r * 0.6)} ${n(x + lean * r)} ${n(by - hg * r)}` +
        `Q${n(x + lean * r * 0.2)} ${n(by - hg * r * 0.5)} ${n(x + r * 0.14)} ${by}Z`;
    })
    .join('');
  return `<path class="bleed-tuft" d="${blades}" style="fill:${sc('foliage-deep')};fill-opacity:.75"/>`;
}

function actorMarkup(a, w, contactY) {
  const vb = /viewBox="([-\d.\s]+)"/.exec(a.svg);
  const [, , vw, vh] = vb[1].trim().split(/\s+/).map(Number);
  const foot = +(/data-foot="([\d.]+)"/.exec(a.svg)?.[1] ?? 1);
  const aw = a.width, ah = (aw * vh) / vw;
  const x = a.x * w - aw / 2, y = contactY - (a.lift || 0) - ah * foot;
  return a.svg.replace('<svg ', `<svg x="${n(x)}" y="${n(y)}" width="${n(aw)}" height="${n(ah)}" overflow="visible" `);
}

export function habitatSVG({ tier = 'thriving', aspect = 'room', title, actors = [], horizon = 0.58, contactLine = 0.84 } = {}) {
  const A = ASPECTS[aspect] || ASPECTS.room;
  const { w, h } = A;
  const id = uid('hab');
  const hy = h * horizon, unit = Math.min(w, h), cy = h * contactLine;
  const bloom = { thriving: 1, good: 0.75 }[tier] ?? 0.55;
  const drifting = tier === 'thriving' || tier === 'good';

  // Sun: one disc, upper left, fully inside the sky and below the top fade.
  const sr = unit * 0.055;
  const sunX = Math.max(w * 0.16, sr * 2.4), sunY = Math.max(h * 0.16, A.fadeTop * 0.55 + sr * 2.2);

  const ramp = (gid, x2, y2) =>
    `<linearGradient id="${id}-${gid}" x1="0" y1="0" x2="${x2}" y2="${y2}">` +
    [[0, 1], [0.35, 0.72], [0.7, 0.22], [1, 0]].map(([o, a]) => `<stop offset="${o}" stop-color="var(--ground)" stop-opacity="${a}"/>`).join('') +
    `</linearGradient>`;

  // Contact shadows, nudged lower-right, away from the light.
  const shadows = (actors.length ? actors.map((a) => ({ x: a.x, f: a.footprint ?? a.width * 0.7, lift: a.lift || 0 })) : [{ x: 0.5, f: unit * 0.3, lift: 0 }])
    .map(({ x, f, lift }) => {
      const sw = f * (lift > 0 ? 0.7 : 1);
      return `<ellipse cx="${n(x * w + sw * 0.05)}" cy="${n(cy + 1)}" rx="${n(sw / 2)}" ry="${n(Math.max(6, sw * 0.16) / 2)}" style="fill:${sc('contact-shadow')};fill-opacity:${lift > 0 ? 0.18 : 0.32}" filter="url(#${id}-cs)"/>`;
    }).join('');

  // Air particles (Good) / sun sparkles (Thriving), seeded like the painter.
  let drift = '';
  if (drifting) {
    const rnd = mulberry(11);
    const sparkle = tier === 'thriving';
    for (let i = 0; i < (sparkle ? 9 : 7); i++) {
      const x = (0.08 + rnd() * 0.88) * w, y = hy * (0.35 + rnd() * 0.55), r = sparkle ? 3 + rnd() * 3 : 1.6 + rnd() * 2;
      const dur = 7 + rnd() * 5, delay = -rnd() * dur, rise = n(hy * 0.18);
      const s = `style="--rise:-${rise}px;animation-duration:${n(dur)}s;animation-delay:${n(delay)}s;transform-origin:${n(x)}px ${n(y)}px"`;
      drift += sparkle
        ? `<g class="lt-drift" ${s} fill="${sc('light')}" fill-opacity=".9">${star(x, y, n(r))}</g>`
        : `<circle class="lt-drift" ${s} cx="${n(x)}" cy="${n(y)}" r="${n(r)}" fill="${sc('light')}" fill-opacity=".75"/>`;
    }
  }

  const far = mix(sc('foliage-deep'), 38, sc('sky-bottom'));
  const near = mix(sc('foliage-deep'), 62, sc('sky-bottom'));
  const gTop = mix(sc('light'), 35, sc('ground')), gBot = mix(sc('foliage'), 25, sc('ground'));
  const rim = mix(sc('light'), 70, sc('ground'));

  return open(`0 0 ${w} ${h}`, `lt-habitat tier-${tier} lt-aspect-${aspect}`, title) +
    `<defs>` +
    `<linearGradient id="${id}-sky" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="${n(hy + 1)}"><stop offset="0" stop-color="${sc('sky-top')}"/><stop offset="1" stop-color="${sc('sky-bottom')}"/></linearGradient>` +
    `<radialGradient id="${id}-bloom" gradientUnits="userSpaceOnUse" cx="${n(w * 0.14)}" cy="${n(h * 0.12)}" r="${n(Math.max(w, h) * 0.55)}"><stop offset="0" stop-color="${sc('light')}" stop-opacity="${n(0.45 * bloom)}"/><stop offset="1" stop-color="${sc('light')}" stop-opacity="0"/></radialGradient>` +
    `<linearGradient id="${id}-gr" gradientUnits="userSpaceOnUse" x1="0" y1="${n(hy - h * 0.04)}" x2="${w}" y2="${n(hy - h * 0.04 + (h - hy))}"><stop offset="0" style="stop-color:${gTop}"/><stop offset="0.45" stop-color="${sc('ground')}"/><stop offset="1" style="stop-color:${gBot}"/></linearGradient>` +
    ramp('ft', 0, 1) + ramp('fb', 0, -1).replace(`x1="0" y1="0" x2="0" y2="-1"`, `x1="0" y1="1" x2="0" y2="0"`) +
    `<filter id="${id}-cs" x="-20%" y="-250%" width="140%" height="600%"><feGaussianBlur stdDeviation="3"/></filter>` +
    `</defs>` +
    // sky, light, hills
    `<rect width="${w}" height="${h}" fill="url(#${id}-sky)"/>` +
    `<rect width="${w}" height="${h}" fill="url(#${id}-bloom)"/>` +
    `<path d="M0 ${n(hy)}L0 ${n(hy - h * 0.1)}Q${n(w * 0.22)} ${n(hy - h * 0.22)} ${n(w * 0.48)} ${n(hy - h * 0.08)}Q${n(w * 0.72)} ${n(hy - h * 0.2)} ${w} ${n(hy - h * 0.12)}L${w} ${n(hy)}Z" style="fill:${far}"/>` +
    `<path d="M${n(w * 0.3)} ${n(hy)}Q${n(w * 0.62)} ${n(hy - h * 0.13)} ${n(w * 1.05)} ${n(hy - h * 0.05)}L${w} ${n(hy)}Z" style="fill:${near}"/>` +
    drift +
    // midground bushes (edge-bleed scenery, never a focal object)
    bush(w * 0.04, hy, unit * 0.13, 1) + bush(w * 0.17, hy + unit * 0.01, unit * 0.08, 2) + bush(w * 0.95, hy - unit * 0.005, unit * 0.15, 3) +
    // ground plane + lit rim
    `<path d="M0 ${n(hy + h * 0.02)}Q${n(w / 2)} ${n(hy - h * 0.035)} ${w} ${n(hy + h * 0.02)}L${w} ${h}L0 ${h}Z" fill="url(#${id}-gr)"/>` +
    `<path d="M0 ${n(hy + h * 0.02)}Q${n(w / 2)} ${n(hy - h * 0.035)} ${w} ${n(hy + h * 0.02)}" fill="none" stroke-width="2" style="stroke:${rim};stroke-opacity:.9"/>` +
    tuft(w * 0.06, h, unit * 0.09) + tuft(w * 0.9, h, unit * 0.07) +
    // feather into the page ground (7b.1)
    `<rect width="${w}" height="${A.fadeTop}" fill="url(#${id}-ft)"/>` +
    `<rect y="${h - A.fadeBottom}" width="${w}" height="${A.fadeBottom}" fill="url(#${id}-fb)"/>` +
    // sun disc, wholly inside the sky
    `<g class="lt-sun" style="transform-origin:${n(sunX)}px ${n(sunY)}px"><circle cx="${n(sunX)}" cy="${n(sunY)}" r="${n(sr * 1.9)}" style="fill:${sc('light')};fill-opacity:.35"/>` +
    `<circle cx="${n(sunX)}" cy="${n(sunY)}" r="${n(sr)}" style="fill:${sc('light')}"/></g>` +
    shadows +
    (actors.length ? actors.map((a) => actorMarkup(a, w, cy)).join('') : '') +
    `</svg>`;
}

// ---- Game health hearts (lt_game_health_meter.dart) ---------------------
// Plain drawn hearts: kept = green, resting = quiet outline. Never red.
export function heartsSVG({ value = 3, max = 3, title } = {}) {
  const sz = 22, gap = 2, W = max * sz + (max - 1) * gap;
  const hearts = Array.from({ length: max }, (_, i) =>
    `<g class="lt-heart${i < value ? ' lt-kept' : ''}" transform="translate(${i * (sz + gap)} 0) scale(${n(sz / 24)})" fill="none" stroke="${i < value ? 'var(--green-600)' : 'var(--baseline)'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS.heart}</g>`).join('');
  return open(`0 0 ${W} ${sz}`, 'lt-hearts', title ?? `Game health: ${value} of ${max} hearts`) + hearts + `</svg>`;
}

// ---- Icons (lt_icon.dart): 24 grid, 2px stroke, round caps and joins -----
const ICONS = {
  room: '<path d="M4 11.5 12 5l8 6.5"/><path d="M6 10.5V19h12v-8.5"/><path d="M10 19v-5h4v5"/>',
  plan: '<rect x="5" y="4" width="14" height="16" rx="3"/><path d="M9 9.5l1.5 1.5L14 7.5"/><path d="M9 15h6"/>',
  activity: '<path d="M3 13h4l2.5-6 4 11 2.5-5H21"/>',
  walk: '<circle cx="13" cy="5" r="1.8"/><path d="M12 9l-2.5 4 2.5 2.5V20"/><path d="M12 9l3 2.5 3 .5"/><path d="M9.5 13l-3 1.5"/>',
  run: '<circle cx="14" cy="5" r="1.8"/><path d="M13 9l-3 3.5 3 2 1 4.5"/><path d="M13 9l4 1 2 3"/><path d="M10 12.5l-4 .5"/>',
  cycle: '<circle cx="6" cy="16" r="3.5"/><circle cx="18" cy="16" r="3.5"/><path d="M6 16l4-8h5l3 8"/><path d="M10 8l3 8"/>',
  swim: '<circle cx="16" cy="6" r="1.8"/><path d="M5 12l5-2 4 2.5"/><path d="M3 17c1.5 1 3 1 4.5 0s3-1 4.5 0 3 1 4.5 0 3-1 4.5 0"/>',
  strength: '<path d="M4 9v6M7 7v10M17 7v10M20 9v6M7 12h10"/>',
  other: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M5 12h14"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  chevronRight: '<path d="M9.5 6l6 6-6 6"/>',
  chevronLeft: '<path d="M14.5 6l-6 6 6 6"/>',
  arrowUp: '<path d="M12 19V6M6.5 11.5 12 6l5.5 5.5"/>',
  arrowDown: '<path d="M12 5v13M6.5 12.5 12 18l5.5-5.5"/>',
  equal: '<path d="M6 9.5h12M6 14.5h12"/>',
  heart: '<path d="M12 19.5S4.5 15 4.5 9.5A3.8 3.8 0 0 1 12 8a3.8 3.8 0 0 1 7.5 1.5c0 5.5-7.5 10-7.5 10z"/>',
  mic: '<rect x="9" y="4" width="6" height="10" rx="3"/><path d="M6 11.5a6 6 0 0 0 12 0M12 17.5V20"/>',
  send: '<path d="M5 12h13M13 6.5 18.5 12 13 17.5"/>',
  lock: '<rect x="6" y="11" width="12" height="9" rx="3"/><path d="M9 11V8.5a3 3 0 0 1 6 0V11"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8v.2"/>',
  sparkle: '<path d="M12 4v5M12 15v5M4 12h5M15 12h5"/>',
  calendar: '<rect x="4.5" y="6" width="15" height="13.5" rx="3"/><path d="M8.5 4v4M15.5 4v4M4.5 10.5h15"/>',
  flask: '<path d="M10 4h4M11 4v5l-5 8.5A2 2 0 0 0 7.7 20.5h8.6a2 2 0 0 0 1.7-3L13 9V4"/>',
  quiz: '<rect x="5" y="4" width="14" height="16" rx="3"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 16.5v.2"/>',
  mirror: '<ellipse cx="12" cy="10" rx="5.5" ry="6.5"/><path d="M12 16.5V20M9 20h6"/>',
  moon: '<path d="M18.5 14.6A7 7 0 0 1 9.4 5.5a7.2 7.2 0 1 0 9.1 9.1z"/>',
  sneaker: '<path d="M3.5 9v8h17v-1.3a2 2 0 0 0-1.6-2l-4.4-.9-3.2-3-1.8 1.4H7.6L6 9z"/><path d="M10.6 12.2l1.2-1M12.8 13.4l1.2-1"/>',
  glass: '<path d="M7 5h10l-1.3 12.8a2 2 0 0 1-2 1.7h-3.4a2 2 0 0 1-2-1.7z"/><path d="M7.7 10.5h8.6"/>',
  leaf: '<path d="M5.5 18.5C5.5 11 10 6 19 5.5c0 8.5-4.8 13-11.5 13z"/><path d="M5.5 18.5l6.5-6.5"/>',
  question: '<circle cx="12" cy="12" r="8.5"/><path d="M9.8 9.7a2.3 2.3 0 1 1 3.2 2.1c-.6.3-1 .8-1 1.5M12 16.2v.2"/>',
  smile: '<circle cx="12" cy="12" r="8.5"/><path d="M8.8 13.6a4 4 0 0 0 6.4 0M9.5 9.8v.2M14.5 9.8v.2"/>',
  ball: '<circle cx="12" cy="11" r="7"/><path d="M8 20h8M9 15.5 8 20M15 15.5 16 20"/>',
};

// Authored in the same family (not in the Flutter set).
ICONS.keyboard = '<rect x="3.5" y="6.5" width="17" height="11" rx="3"/><path d="M7.5 10.5v.2M11 10.5v.2M14.5 10.5v.2M16.5 13.8v.2M7.5 13.8h6.5"/>';
ICONS.refresh = '<path d="M19 12a7 7 0 1 1-2.1-5"/><path d="M19 4.8v4.4h-4.4"/>';

const ALIASES = { sleep: 'moon', drinks: 'glass', food: 'leaf', shoe: 'sneaker', 'arrow-up': 'arrowUp', 'arrow-down': 'arrowDown', 'chevron-right': 'chevronRight', 'chevron-left': 'chevronLeft', reload: 'refresh' };
export const iconNames = Object.keys(ICONS);

export function iconSVG(name, { title } = {}) {
  const body = ICONS[ALIASES[name] || name];
  if (!body) throw new Error(`Unknown icon "${name}". Known: ${[...iconNames, ...Object.keys(ALIASES)].join(', ')}`);
  return open('0 0 24 24', 'lt-icon', title, 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"') + body + `</svg>`;
}
