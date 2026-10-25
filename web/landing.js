import { twinSVG, pipSVG, habitatSVG, heartsSVG, iconSVG } from './shared/art.js';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const slot = (name) => $(`[data-slot="${name}"]`);
const par = (svg, v) => svg.replace('<svg ', `<svg preserveAspectRatio="${v}" `);
const reduce = matchMedia('(prefers-reduced-motion: reduce)');

// ---- twin looks ---------------------------------------------------------
const BASE = { skin: 2, hair: 'bob', hairColor: 'brown', top: 'blue' };
const twin = (o) => twinSVG({ ...BASE, ...o });
const TWIN = {
  base: twin({ mood: 'happy' }),
  looks: twin({ mood: 'happy', skin: 3, hair: 'curly', hairColor: 'auburn', top: 'sun', pose: 'wave' }),
  health: twin({ mood: 'sick' }),
  answers: twin({ mood: 'calm' }),
  experiments: twin({ mood: 'thinking' }),
};
const PIP = {
  idle: pipSVG({ state: 'idle', shadow: true }),
  listening: pipSVG({ state: 'listening', shadow: true }),
  thinking: pipSVG({ state: 'thinking', shadow: true }),
  celebrating: pipSVG({ state: 'celebrating', shadow: true }),
};

const stackHTML = (map, on) =>
  Object.entries(map).map(([k, svg]) => `<div class="v${k === on ? ' on' : ''}" data-v="${k}">${svg}</div>`).join('');
const setStack = (el, key) => $$('.v', el).forEach((v) => v.classList.toggle('on', v.dataset.v === key));

// ---- icons --------------------------------------------------------------
$$('[data-icon]').forEach((el) => { el.innerHTML = iconSVG(el.dataset.icon); });
slot('brand-pip').innerHTML = pipSVG({ state: 'idle' });

// ---- hero habitat: one bare scene per aspect (actors are HTML so they can react)
const NONE = [{ svg: '<svg viewBox="0 0 1 1" data-foot="1"></svg>', x: 0.5, width: 0.01, footprint: 0.01 }];
slot('hero-habitat').innerHTML =
  par(habitatSVG({ tier: 'thriving', aspect: 'wide', actors: NONE }), 'xMinYMid slice').replace('lt-svg ', 'lt-svg hab-wide ') +
  par(habitatSVG({ tier: 'thriving', aspect: 'room', actors: NONE }), 'xMinYMid slice').replace('lt-svg ', 'lt-svg hab-room ');

$('#twin-stack').innerHTML = stackHTML(TWIN, 'base');
$('#pip-stack').innerHTML = stackHTML(PIP, 'idle');

// ---- jars (authored glass jars) ----------------------------------------
const HEART = 'M12 19.5S4.5 15 4.5 9.5A3.8 3.8 0 0 1 12 8a3.8 3.8 0 0 1 7.5 1.5c0 5.5-7.5 10-7.5 10z';
const heartAt = (x, y, s, filled) =>
  `<g transform="translate(${x} ${y}) scale(${s})"><path d="${HEART}" transform="translate(-12 -12)" ${filled
    ? 'fill="var(--green-400)" stroke="var(--green-600)"'
    : 'fill="var(--surface)" fill-opacity=".6" stroke="var(--baseline)"'} stroke-width="${(2 / s).toFixed(2)}" stroke-linejoin="round"/></g>`;

const JAR = {
  looks: {
    lid: 'var(--lavender-100)', floor: 'var(--lavender-100)',
    inside:
      `<path d="M30 80 L43 72 Q51 80 59 72 L72 80 L66 94 L61 90 V120 H41 V90 L36 94 Z" fill="var(--blue-600)"/>` +
      `<path d="M43 72 Q51 80 59 72" fill="none" stroke="var(--surface)" stroke-opacity=".6" stroke-width="2" stroke-linecap="round"/>` +
      `<rect x="78" y="88" width="16" height="30" rx="8" fill="var(--ink)" transform="rotate(10 86 103)"/>` +
      `<path d="M83 94 q3 8 1 18" fill="none" stroke="var(--surface)" stroke-opacity=".5" stroke-width="2" stroke-linecap="round" transform="rotate(10 86 103)"/>`,
  },
  health: {
    lid: 'var(--green-600)', floor: 'var(--green-100)',
    inside: heartAt(46, 92, 2.2, true) + heartAt(76, 92, 2.2, true) + heartAt(61, 116, 2.2, false),
  },
  answers: {
    lid: 'var(--blue-600)', floor: 'var(--blue-100)',
    inside:
      `<rect x="32" y="70" width="52" height="50" rx="9" fill="var(--surface)" stroke="var(--blue-400)" stroke-width="2"/>` +
      `<path d="M41 85h26M41 95h18" stroke="var(--ink-2)" stroke-width="3" stroke-linecap="round"/>` +
      `<circle cx="80" cy="113" r="11" fill="var(--green-600)" stroke="var(--surface)" stroke-width="2.5"/>` +
      `<path d="M74.5 113l4 4 7-8" fill="none" stroke="var(--surface)" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  experiments: {
    lid: 'var(--blue-400)', floor: 'var(--green-100)',
    inside:
      `<path d="M52 66H68V84L83 114Q87 123 78 123H42Q33 123 37 114L52 84Z" fill="var(--surface)" fill-opacity=".7" stroke="var(--ink-2)" stroke-width="2.4" stroke-linejoin="round"/>` +
      `<path d="M44 104H76L81 114Q83 119 78 119H42Q37 119 39 114Z" fill="var(--green-400)"/>` +
      `<circle class="bub" cx="55" cy="96" r="3" fill="var(--surface)" fill-opacity=".9"/>` +
      `<circle class="bub b2" cx="66" cy="90" r="2.4" fill="var(--blue-400)"/>` +
      `<circle class="bub b3" cx="60" cy="76" r="2" fill="var(--blue-400)"/>`,
  },
};

function jarSVG(kind) {
  const j = JAR[kind];
  const body = 'M38 42H82V54C108 60 112 84 112 100C112 126 94 140 60 140C26 140 8 126 8 100C8 84 12 60 38 54Z';
  return `<svg class="jar-svg" viewBox="-6 0 132 152" aria-hidden="true" focusable="false">` +
    `<ellipse class="jar-shadow" cx="60" cy="144" rx="42" ry="5" fill="var(--ink)" fill-opacity=".14"/>` +
    `<g class="jar-body">` +
      `<path d="${body}" fill="var(--surface)" fill-opacity=".34"/>` +
      `<ellipse cx="60" cy="126" rx="36" ry="9" fill="${j.floor}" fill-opacity=".85"/>` +
      `<g class="jar-in">${j.inside}</g>` +
      `<path d="${body}" fill="none" stroke="var(--surface)" stroke-width="3.5" stroke-linejoin="round"/>` +
      `<path d="M20 98C20 84 24 70 36 64" fill="none" stroke="var(--surface)" stroke-width="4.5" stroke-linecap="round" stroke-opacity=".9"/>` +
      `<rect x="35" y="40" width="50" height="6" rx="3" fill="var(--surface)" fill-opacity=".85"/>` +
    `</g>` +
    `<g class="jar-lid">` +
      `<rect x="31" y="22" width="58" height="20" rx="8" fill="${j.lid}" stroke="color-mix(in srgb, var(--ink) 30%, ${j.lid})" stroke-width="2"/>` +
      `<path d="M40 28V37M50 28V37M60 28V37M70 28V37M80 28V37" stroke="color-mix(in srgb, var(--ink) 18%, ${j.lid})" stroke-width="2" stroke-linecap="round"/>` +
    `</g></svg>`;
}
$$('[data-jar-art]').forEach((el) => { el.innerHTML = jarSVG(el.dataset.jarArt); });

// ---- signature: a jar lifts its lid and the twin reacts ---------------------
const REACT = {
  looks: { twin: 'looks', pip: 'celebrating', lean: -1, say: 'Looks never change a single number.' },
  health: { twin: 'health', pip: 'idle', lean: -1, say: 'Wrong answers just make us sniffle.' },
  answers: { twin: 'base', pip: 'listening', lean: 1, say: 'I only keep what you say yes to.' },
  experiments: { twin: 'base', pip: 'thinking', lean: 1, say: 'Try it on a copy. Reset any time.' },
};
const lean = $('#twin-lean'), twinStack = $('#twin-stack'), pipStack = $('#pip-stack');
const bubble = $('#bubble'), bubbleText = $('#bubble-text');
const HELLO = 'Hi! Pick a jar.';
let openJar = null;

function react(jar, key) {
  const r = REACT[key];
  if (openJar && openJar !== jar) openJar.classList.remove('is-open');
  jar.classList.add('is-open');
  openJar = jar;
  setStack(twinStack, r.twin);
  setStack(pipStack, r.pip);
  lean.style.setProperty('--lx', `${r.lean * 14}px`);
  lean.style.setProperty('--lr', `${r.lean * 3.5}deg`);
  bubbleText.textContent = r.say;
}
function rest(jar) {
  jar.classList.remove('is-open');
  if (openJar !== jar) return;
  openJar = null;
  setStack(twinStack, 'base');
  setStack(pipStack, 'idle');
  lean.style.setProperty('--lx', '0px');
  lean.style.setProperty('--lr', '0deg');
  bubbleText.textContent = HELLO;
}
$$('.jar').forEach((jar) => {
  const key = jar.dataset.jar;
  jar.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') react(jar, key); });
  jar.addEventListener('pointerleave', (e) => { if (e.pointerType === 'mouse' && document.activeElement !== jar) rest(jar); });
  jar.addEventListener('focus', () => react(jar, key));
  jar.addEventListener('blur', () => rest(jar));
});

// ---- Looks: three different twins, the same numbers ---------------------
const LOOKS = [
  twin({ mood: 'happy' }),
  twin({ mood: 'happy', skin: 4, hair: 'curly', hairColor: 'silver', top: 'green', extra: 'glasses' }),
  twin({ mood: 'happy', skin: 1, hair: 'short', hairColor: 'blonde', top: 'sun', extra: 'headband' }),
];
slot('looks-art').innerHTML = LOOKS.map((svg, i) =>
  (i ? `<span class="same ic" aria-label="same as">${iconSVG('equal')}</span>` : '') +
  `<figure class="look"><div class="look-twin">${svg}<span class="gshadow"></span></div><figcaption class="num">[xx %]</figcaption></figure>`
).join('');

// ---- Game health: a wrong answer only touches the hearts -----------------
slot('health-art').innerHTML =
  `<div class="health-grid">` +
    `<div class="health-twin"><div class="stack" id="h-twin">${stackHTML({ sick: twin({ mood: 'sick', skin: 3 }), well: twin({ mood: 'recovering', skin: 3 }) }, 'sick')}</div><span class="gshadow"></span></div>` +
    `<div class="health-side">` +
      `<div class="hearts stack" id="h-hearts">${stackHTML({ sick: heartsSVG({ value: 2, max: 3 }), well: heartsSVG({ value: 3, max: 3 }) }, 'sick')}</div>` +
      `<p class="outlook"><span>Outlook</span><span class="num">[xx %]</span></p>` +
      `<div class="seg" role="group" aria-label="Quiz answer">` +
        `<button type="button" aria-pressed="true" data-h="sick"><span class="ic">${iconSVG('close')}</span>Wrong answer</button>` +
        `<button type="button" aria-pressed="false" data-h="well"><span class="ic">${iconSVG('check')}</span>Right answer</button>` +
      `</div>` +
      `<p class="status" id="h-status" aria-live="polite">Sniffle! Outlook did not move.</p>` +
    `</div>` +
  `</div>`;
$$('[data-h]').forEach((b) => b.addEventListener('click', () => {
  const k = b.dataset.h;
  setStack($('#h-twin'), k);
  setStack($('#h-hearts'), k);
  $$('[data-h]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
  $('#h-status').textContent = k === 'sick' ? 'Sniffle! Outlook did not move.' : 'Better! Outlook did not move.';
}));

// ---- Your answers: Pip checks, you say yes -------------------------------
slot('answers-art').innerHTML =
  `<div class="chat">` +
    `<div class="chat-pip"><div class="stack" id="a-pip">${stackHTML({ idle: PIP.idle, listening: PIP.listening, celebrating: PIP.celebrating }, 'idle')}</div></div>` +
    `<div class="chat-col">` +
      `<div class="say" id="a-say" aria-live="polite"><span id="a-text">Sleep is 7 hours. Is that right?</span></div>` +
      `<div class="chat-act" id="a-act">` +
        `<button type="button" class="btn-sm btn-sm-fill" data-a="yes">Yes</button>` +
        `<button type="button" class="btn-sm btn-sm-ghost" data-a="fix">Fix it</button>` +
      `</div>` +
      `<p class="kept" id="a-kept" hidden><span class="ic">${iconSVG('check')}</span>Kept</p>` +
      `<p class="cap">Example chat</p>` +
    `</div>` +
  `</div>`;
const A = {
  ask: { text: 'Sleep is 7 hours. Is that right?', pip: 'idle', acts: true, kept: false },
  yes: { text: 'Thank you! I wrote it down.', pip: 'celebrating', acts: false, kept: true },
  fix: { text: 'No problem. Tell me the right number.', pip: 'listening', acts: false, kept: false },
};
function ask(state) {
  const s = A[state];
  $('#a-text').textContent = s.text;
  setStack($('#a-pip'), s.pip);
  $('#a-kept').hidden = !s.kept;
  const act = $('#a-act');
  act.innerHTML = s.acts
    ? `<button type="button" class="btn-sm btn-sm-fill" data-a="yes">Yes</button><button type="button" class="btn-sm btn-sm-ghost" data-a="fix">Fix it</button>`
    : `<button type="button" class="btn-sm btn-sm-ghost" data-a="ask">Ask again</button>`;
}
$('#a-act').addEventListener('click', (e) => {
  const b = e.target.closest('[data-a]');
  if (!b) return;
  ask(b.dataset.a);
  $('#a-act button')?.focus();
});

// ---- Experiments: change the copy, the real twin stays put ---------------
const dome = (inner, label) =>
  `<div class="dome-wrap"><div class="dome">${inner}</div><p class="who">${label}</p></div>`;
const domeSVG =
  `<svg class="dome-glass" viewBox="0 0 100 106" aria-hidden="true" focusable="false">` +
  `<ellipse cx="50" cy="98" rx="34" ry="5" fill="var(--ink)" fill-opacity=".12"/>` +
  `<circle cx="50" cy="50" r="46" fill="var(--surface)" fill-opacity=".16"/>` +
  `<circle cx="50" cy="50" r="46" fill="none" stroke="var(--surface)" stroke-width="2.6"/>` +
  `<path d="M16 46C17 32 26 21 38 16" fill="none" stroke="var(--surface)" stroke-width="3.4" stroke-linecap="round"/></svg>`;
slot('exp-art').innerHTML =
  `<div class="exp-grid">` +
    `<div class="exp-real"><div class="real-twin">${twin({ mood: 'calm' })}<span class="gshadow"></span></div><p class="who">Your twin</p><p class="num">[xx %]</p></div>` +
    `<span class="exp-link ic" aria-hidden="true">${iconSVG('chevronRight')}</span>` +
    `<div class="exp-copy">` +
      dome(`<div class="stack" id="e-twin">${stackHTML({
        calm: twin({ mood: 'calm' }),
        changed: twin({ mood: 'recovering', pose: 'cheer' }),
      }, 'calm')}</div>${domeSVG}`, 'Copy') +
      `<p class="num" id="e-num" aria-live="polite">[xx %]</p>` +
      `<div class="seg" role="group" aria-label="Experiment">` +
        `<button type="button" data-e="changed" aria-pressed="false">Try a change</button>` +
        `<button type="button" data-e="calm" aria-pressed="true">Reset</button>` +
      `</div>` +
    `</div>` +
  `</div>`;
$$('[data-e]').forEach((b) => b.addEventListener('click', () => {
  const k = b.dataset.e;
  setStack($('#e-twin'), k);
  $('#e-num').textContent = k === 'changed' ? '[± x.x pts]' : '[xx %]';
  $$('[data-e]').forEach((x) => x.setAttribute('aria-pressed', String(x.dataset.e === k)));
}));

// ---- closing band --------------------------------------------------------
const closeActors = (tx, tw, px, pw) => [
  { svg: twin({ mood: 'happy', skin: 2, pose: 'cheer' }), x: tx, width: tw },
  { svg: pipSVG({ state: 'celebrating' }), x: px, width: pw, lift: 10, footprint: pw * 0.6 },
];
slot('close-habitat').innerHTML =
  habitatSVG({ tier: 'thriving', aspect: 'wide', actors: closeActors(0.62, 190, 0.8, 120) }).replace('lt-svg ', 'lt-svg hab-wide ') +
  habitatSVG({ tier: 'thriving', aspect: 'room', actors: closeActors(0.34, 150, 0.72, 100) }).replace('lt-svg ', 'lt-svg hab-room ');

// ---- the one load moment: wait for the type, then go ------------------------
const go = () => document.documentElement.classList.add('go');
if (reduce.matches || !document.fonts) go();
else Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 900))]).then(() => requestAnimationFrame(go));
