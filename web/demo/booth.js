// Try to trick Pip: the judge booth. Intake goes to the real keyless parser
// (POST /api/onboarding/turn); when it can't be reached, a recorded run from
// the same server plays instead and says so. Prediction is deferred, so the
// fortune only ever shows labeled placeholders.
import { twinSVG, pipSVG, magicBallSVG, habitatSVG, iconSVG } from '../shared/art.js';

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const API = (params.get('api') || 'http://127.0.0.1:8000').replace(/\/$/, '');
const FORCE_REPLAY = params.has('replay');
const IDLE_MS = 60_000;
const HAB = { w: 960, h: 420, contact: 0.84 };
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

const SEX = { female: 'Female', male: 'Male', intersex: 'Intersex', prefer_not_to_say: 'Not saying' };
const SMOKE = { never: 'Never', former: 'Used to', current: 'Smokes', unknown: 'Not sure' };
const num = (v) => String(Math.round(v * 10) / 10);
const ftIn = (cm) => {
  let ft = Math.floor(cm / 30.48), inch = Math.round(cm / 2.54 - ft * 12);
  if (inch === 12) { ft += 1; inch = 0; }
  return `${ft} ft ${inch}`;
};
const SLOTS = [
  { key: 'age', label: 'Age', fmt: (p) => p.age != null && `${p.age}` },
  { key: 'sex', label: 'Sex', fmt: (p) => p.sex && SEX[p.sex] },
  { key: 'height_cm', label: 'Height', fmt: (p) => p.height_cm != null && ftIn(p.height_cm) },
  { key: 'weight_kg', label: 'Weight', fmt: (p) => p.weight_kg != null && `${Math.round(p.weight_kg * 2.20462)} lb` },
  { key: 'sleep_hours', label: 'Sleep', fmt: (p) => p.sleep_hours != null && `${num(p.sleep_hours)} h` },
  { key: 'exercise_minutes_weekly', label: 'Exercise', fmt: (p) => p.exercise_minutes_weekly != null && `${p.exercise_minutes_weekly} min/wk` },
  { key: 'smoking_status', label: 'Smoking', fmt: (p) => p.smoking_status && SMOKE[p.smoking_status] },
  { key: 'alcohol_drinks_weekly', label: 'Drinks', fmt: (p) => p.alcohol_drinks_weekly != null && `${num(p.alcohol_drinks_weekly)}/wk` },
  { key: 'diabetes', label: 'Diabetes', fmt: (p) => p.diabetes != null && (p.diabetes ? 'Yes' : 'No') },
  { key: 'systolic_bp', also: 'diastolic_bp', label: 'Blood pressure', fmt: (p) => p.systolic_bp != null && `${p.systolic_bp}/${p.diastolic_bp ?? '?'}` },
];
// Suggestions mix answers Pip understands with ones it should ask about.
const HINTS = {
  age: ['thirty four', '34yo', 'old enough'],
  sex: ['female', 'femail', 'prefer not to say'],
  height_cm: [`6'1"`, '170', 'five foot ten'],
  weight_kg: ['two hundred pounds', '170', 'about 80 kilos'],
  sleep_hours: ['around 7-8 hours', '6ish', 'not enough'],
  exercise_minutes_weekly: ['I run 3 times a week for 30 minutes', 'an hour a day', "I don't exercise"],
  smoking_status: ['I quit smoking 5 years ago', 'I vape sometimes', 'never'],
  alcohol_drinks_weekly: ["I don't drink", 'a glass of wine with dinner', 'a couple beers on weekends'],
  diabetes: ['I have type 2', 'no', 'my dad has it'],
  systolic_bp: ['120 over 80', '120 80', "I don't know"],
  diastolic_bp: ['80', "I don't know"],
};
const LOOKS = [
  { skin: 1, hair: 'bob', hairColor: 'brown', top: 'blue' },
  { skin: 3, hair: 'curly', hairColor: 'black', top: 'green' },
  { skin: 4, hair: 'short', hairColor: 'black', top: 'sun', extra: 'glasses' },
  { skin: 2, hair: 'short', hairColor: 'auburn', top: 'sky' },
  { skin: 5, hair: 'curly', hairColor: 'silver', top: 'blue', extra: 'glasses' },
];

const S = {
  mode: 'loading', // 'live' | 'replay'
  attract: false,
  scene: 'talk',
  turn: null,
  busy: false,
  tally: { understood: 0, again: 0, unasked: 0 },
  look: LOOKS[0],
  twinMood: 'happy',
  pipState: 'idle',
  replay: null,
  quiz: null,
  health: 100,
  qIndex: 0,
  scored: new Set(),
  reviewed: new Set(),
};
let attractToken = 0;
let idleTimer = 0;
let pipTimer = 0;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pace = (ms) => sleep(reduceMotion.matches ? Math.min(ms, 900) : ms);

// ---------- server ----------

class Offline extends Error {}

async function api(path, body) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const res = await fetch(API + path, body === undefined ? { signal: ctrl.signal } : {
      method: 'POST', signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) throw Object.assign(new Error(`HTTP ${res.status}`), { status: res.status, data });
    return data;
  } catch (err) {
    if (err.status) throw err;
    throw new Offline(err.message);
  } finally {
    clearTimeout(timer);
  }
}

async function detectMode() {
  if (!FORCE_REPLAY) {
    try { await api('/health'); return 'live'; } catch { /* fall through */ }
  }
  return 'replay';
}

// ---------- scene ----------

function drawScene() {
  $('scene').innerHTML = habitatSVG({ tier: 'good', aspect: 'wide' });
  $('scene').firstElementChild.setAttribute('preserveAspectRatio', 'xMidYMax slice');
}

function drawTwin() { $('twin').innerHTML = twinSVG({ ...S.look, mood: S.twinMood, title: `Your twin looks ${S.twinMood}` }); }
function drawPip() { $('pip').innerHTML = pipSVG({ state: S.pipState, title: 'Pip' }); }
function setTwin(mood) { if (mood !== S.twinMood) { S.twinMood = mood; drawTwin(); } }
function setPip(state, holdMs) {
  clearTimeout(pipTimer);
  if (state !== S.pipState) { S.pipState = state; drawPip(); }
  if (holdMs) pipTimer = setTimeout(() => setPip('idle'), holdMs);
}

// Actor positions per scene, as fractions of the habitat width.
const SPOTS = {
  talk: { twin: 0.25, pip: 0.47 },
  fortune: { twin: 0.17, pip: 0.33, ball: 0.43 },
  quiz: { twin: 0.17, pip: 0.33 },
};
const SIZES = { twin: 128, pip: 100, ball: 74 }; // habitat units
const ASPECT = { twin: 172 / 144, pip: 116 / 108, ball: 1.12 };
const FOOT = { twin: 168 / 172, pip: 102 / 116, ball: 0.96 };

function layout() {
  const stage = $('scene').getBoundingClientRect();
  const s = Math.max(stage.width / HAB.w, stage.height / HAB.h);
  const zoom = S.scene === 'talk' ? 1 : 0.85;
  const ox = (stage.width - HAB.w * s) / 2;
  const contact = stage.height - HAB.h * s * (1 - HAB.contact);
  const spots = SPOTS[S.scene];
  const root = $('stage').style;
  root.setProperty('--contact', `${contact}px`);
  root.setProperty('--header-h', `${document.querySelector('.top').getBoundingClientRect().bottom}px`);
  for (const who of ['twin', 'pip', 'ball']) {
    const el = $(who);
    if (spots[who] == null) continue;
    const w = SIZES[who] * s * zoom, h = w * ASPECT[who];
    const x = ox + spots[who] * HAB.w * s;
    el.style.width = `${w}px`;
    el.style.left = `${x - w / 2}px`;
    el.style.top = `${contact - h * FOOT[who]}px`;
    root.setProperty(`--${who}-x`, `${x}px`);
    root.setProperty(`--${who}-w`, `${w}px`);
    root.setProperty(`--${who}-top`, `${contact - h * FOOT[who]}px`);
  }
}

// ---------- Pip's words ----------

// Server messages stay verbatim; this only decides which sentence is big.
function splitMessage(msg) {
  const heard = msg.match(/^(.*?)Here is what I heard\.\s*(.+?)\s*Is that right\?/s);
  if (heard) return { lead: heard[1].trim(), ask: 'Is that right?', heard: heard[2].replace(/\.$/, ''), after: '' };
  const parts = msg.match(/[^.?!]+[.?!]+["”]?/g) || [msg];
  const q = parts.findIndex((p) => p.trim().endsWith('?'));
  if (q === -1) return { lead: '', ask: msg, after: '' };
  return {
    lead: parts.slice(0, q).join(' ').trim(),
    ask: parts[q].trim(),
    after: parts.slice(q + 1).join(' ').trim(),
  };
}

function say({ lead = '', ask = '', after = '', heard = null, said = '', actions = [] }) {
  $('pip-lead').textContent = lead;
  $('pip-lead').hidden = !lead;
  $('pip-ask').textContent = ask;
  const box = $('heard');
  box.hidden = !heard;
  box.classList.remove('morph');
  if (heard) {
    $('heard-said').textContent = said ? `“${said}”` : '';
    $('heard-value').textContent = heard;
    void box.offsetWidth; // restart the morph
    box.classList.add('morph');
  }
  const after_ = $('pip-bubble').querySelector('.after') || Object.assign(document.createElement('p'), { className: 'after' });
  after_.textContent = after;
  after_.hidden = !after;
  $('pip-ask').after(after_);
  const row = $('pip-actions');
  row.replaceChildren(...actions.map(({ label, kind = 'ghost', run }) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = kind;
    b.textContent = label;
    b.addEventListener('click', run);
    return b;
  }));
  row.hidden = actions.length === 0;
}

function youSaid(text) {
  const b = $('you-bubble');
  b.textContent = text;
  b.hidden = !text;
}

// ---------- answers + score ----------

function drawSlots(state) {
  const conf = state?.confirmed_profile ?? {};
  const pend = state?.pending_profile ?? {};
  const skipped = new Set(state?.skipped_fields ?? []);
  const current = state?.current_field;
  $('slots').replaceChildren(...SLOTS.map((slot) => {
    const li = document.createElement('li');
    const value = slot.fmt(conf);
    const checking = state?.phase === 'confirming' && (pend[slot.key] != null || (slot.also && pend[slot.also] != null));
    li.className = value ? 'kept' : checking ? 'checking' : skipped.has(slot.key) ? 'skipped' : '';
    if (!value && !checking && (current === slot.key || current === slot.also)) li.classList.add('now');
    li.innerHTML = `<span class="slot-label"></span><span class="slot-value"></span>`;
    li.firstChild.textContent = slot.label;
    li.lastChild.textContent = value || (checking ? 'Checking' : skipped.has(slot.key) ? 'Skipped' : '—');
    if (value) li.insertAdjacentHTML('afterbegin', `<span class="slot-tick">${iconSVG('check')}</span>`);
    return li;
  }));
}

function bump(id, value) {
  const el = $(id);
  el.textContent = value;
  el.classList.remove('bump');
  void el.offsetWidth;
  el.classList.add('bump');
}

// Classify a turn and run the one invariant the booth advertises: a value
// may only become confirmed if it was read back (pending) right before.
function score(prev, next, kind) {
  const before = prev?.state, after = next.state;
  for (const [field, value] of Object.entries(after.confirmed_profile)) {
    const was = before?.confirmed_profile?.[field] ?? null;
    if (value === null || value === was) continue;
    const readBack = before?.phase === 'confirming' && before.pending_profile[field] === value;
    if (!readBack) bump('s-unasked', ++S.tally.unasked);
  }
  if (kind !== 'reply') return 'other';
  const newConfirmed = Object.keys(after.confirmed_profile).some(
    (f) => after.confirmed_profile[f] !== (before?.confirmed_profile?.[f] ?? null));
  if (newConfirmed) return 'yes';
  if ((after.skipped_fields?.length ?? 0) > (before?.skipped_fields?.length ?? 0)) return 'skip';
  if (after.phase === 'confirming' && JSON.stringify(after.pending_profile) !== JSON.stringify(before?.pending_profile)) {
    bump('s-understood', ++S.tally.understood);
    return 'understood';
  }
  bump('s-again', ++S.tally.again);
  return 'again';
}

// ---------- the conversation ----------

let replayCursor = 0;
async function send(body) {
  if (S.mode === 'live') {
    try {
      return await api('/api/onboarding/turn', body);
    } catch (err) {
      if (!(err instanceof Offline)) throw err;
      await goReplay('Pip lost the internet. Here is a recorded run.');
      throw err;
    }
  }
  const step = S.replay.script[replayCursor++];
  if (!step) throw new Offline('end of replay');
  return step.response;
}

function render(res, { kind, text = '' }) {
  const prev = S.turn;
  S.turn = res;
  const verdict = score(prev, res, kind);
  drawSlots(res.state);
  const parts = splitMessage(res.message);
  if (kind === 'start') parts.lead = ''; // the greeting is long; the question is what matters
  const event = res.mascot_events?.at(-1)?.state ?? 'asking';
  const actions = [];
  if (res.complete) {
    setPip('celebrating', 3200);
    setTwin('happy');
    actions.push({ label: 'See my fortune', kind: 'primary', run: () => go('fortune') });
  } else if (res.state.phase === 'confirming') {
    setPip('listening');
    actions.push({ label: "Yes, that's right", kind: 'primary', run: () => act({ action: 'confirm' }) });
    actions.push({ label: 'Not quite', run: () => { $('say-input').placeholder = 'Type the right answer'; $('say-input').focus(); } });
  } else {
    setPip(event === 'celebrating' ? 'celebrating' : 'speaking', 2200);
    if (res.state.current_field) actions.push({ label: 'Skip', run: () => act({ action: 'skip', field: res.state.current_field }) });
  }
  setTwin(verdict === 'again' ? 'thinking' : 'happy');
  say({ ...parts, said: text, actions });
  drawHints(res);
  $('say-input').placeholder = 'Type an answer, any way you like';
}

function drawHints(res) {
  const field = res?.state?.current_field;
  const list = res?.state?.phase === 'confirming' ? ['yes', 'yep', 'sure'] : HINTS[field] ?? [];
  const live = S.mode === 'live' && !S.attract;
  $('hints').replaceChildren(...(list.length ? [Object.assign(document.createElement('span'), { className: 'hints-label', textContent: 'Try:' })] : []),
    ...list.map((text) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = text;
      b.disabled = !live;
      b.addEventListener('click', () => reply(text));
      return b;
    }));
}

async function act(extra, text = '') {
  if (S.busy || !S.turn) return;
  S.busy = true;
  document.body.classList.add('busy');
  setPip('thinking');
  try {
    const res = await send({ ...extra, state: S.turn.state });
    render(res, { kind: extra.action, text });
  } catch (err) {
    if (err instanceof Offline) return;
    const tooFast = err.status === 429;
    setPip('idle');
    say({
      ask: tooFast ? 'Pip needs a short breather.' : "Pip couldn't read that one.",
      after: tooFast ? 'Try again in a few seconds.' : (err.data?.message || 'Try saying it another way.'),
    });
  } finally {
    S.busy = false;
    document.body.classList.remove('busy');
  }
}

function reply(text) {
  text = text.trim();
  if (!text || S.busy) return;
  youSaid(text);
  $('say-input').value = '';
  return act({ action: 'reply', text }, text);
}

async function startTalk() {
  S.turn = null;
  replayCursor = 0;
  youSaid('');
  drawSlots(null);
  setPip('thinking');
  try {
    const res = await send({ action: 'start' });
    replayCursor = Math.max(replayCursor, 1);
    render(res, { kind: 'start' });
  } catch (err) {
    if (!(err instanceof Offline)) say({ ask: "Pip can't start right now.", after: 'Press Start over to try again.' });
  }
}

// ---------- scenes ----------

const TITLES = { talk: 'Try to trick Pip', fortune: 'Your fortune', quiz: 'Quiz time' };

function setScene(scene) {
  S.scene = scene;
  document.body.dataset.scene = scene;
  document.querySelector('.title').textContent = TITLES[scene];
  document.querySelectorAll('.steps [data-go]').forEach((b) => {
    if (b.dataset.go === scene) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current');
  });
  $('ball').hidden = scene !== 'fortune';
  $('panel').hidden = scene === 'talk';
  layout();
}

function go(scene) {
  if (S.scene === scene && scene !== 'talk') return;
  setScene(scene);
  if (scene === 'fortune') showFortune();
  if (scene === 'quiz') showQuiz();
  if (scene === 'talk') {
    if (S.turn) render(S.turn, { kind: 'resume' }); else startTalk();
  }
}

function showFortune() {
  $('ball').innerHTML = magicBallSVG({ glow: 0.9, title: 'Magic ball' });
  setPip('speaking', 2600);
  setTwin('calm');
  youSaid('');
  say({
    ask: 'My ball is still learning.',
    after: 'Your real outlook appears once the model is connected.',
    actions: [{ label: 'Play the quiz', kind: 'primary', run: () => go('quiz') }],
  });
  $('panel').innerHTML = `
    <h2 class="panel-title">Your outlook</h2>
    <div class="outlook">
      <p class="outlook-row big"><span class="ph">[xx %]</span><span>at 10 years</span></p>
      <p class="outlook-row"><span class="ph">[xx %]</span><span>at 20 years</span></p>
      <svg class="curve" viewBox="0 0 320 120" role="img" aria-label="Example curve shape, not your data">
        <path d="M8 14 C 90 16, 150 30, 200 56 S 290 104, 312 108" fill="none" stroke="var(--blue-600)" stroke-width="3" stroke-linecap="round" stroke-dasharray="2 9"/>
        <path d="M8 112 H 312" stroke="var(--line)" stroke-width="2"/>
      </svg>
    </div>
    <button type="button" class="note" data-why>${iconSVG('info')}<span>Example numbers · linked, not proven</span></button>`;
  $('panel').querySelector('[data-why]').addEventListener('click', () => $('why').showModal());
}

async function loadQuiz() {
  if (S.quiz) return S.quiz;
  if (S.mode === 'live') {
    try { S.quiz = await api('/api/quiz/questions'); return S.quiz; } catch { /* use the recorded bank */ }
  }
  S.quiz = S.replay.quiz;
  return S.quiz;
}

function healthMeter() {
  const pct = Math.max(0, Math.min(100, S.health));
  return `<div class="meter" role="meter" aria-label="Game health" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${pct}">
    <span class="meter-label">${iconSVG('heart')} Game health</span>
    <span class="meter-bar"><span style="transform:scaleX(${pct / 100})"></span></span>
    <span class="meter-num">${pct}</span></div>`;
}

async function showQuiz() {
  youSaid('');
  setTwin('happy');
  const bank = await loadQuiz();
  const qs = bank.questions;
  if (S.qIndex >= qs.length) {
    setPip('celebrating', 3000);
    say({ ask: "That's the whole quiz!", after: 'Your answers never changed.', actions: [{ label: 'Start over', kind: 'primary', run: restart }] });
    $('panel').innerHTML = healthMeter();
    return;
  }
  const q = qs[S.qIndex];
  setPip('speaking', 1800);
  say({ ask: 'Quick question for you.', after: `${S.qIndex + 1} of ${qs.length}` });
  $('panel').innerHTML = `${healthMeter()}
    <p class="q-text"></p>
    <div class="options" role="group" aria-label="Answers"></div>
    <div class="q-result" aria-live="polite" hidden></div>`;
  $('panel').querySelector('.q-text').textContent = q.scenario;
  const opts = $('panel').querySelector('.options');
  for (const o of q.options) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'option';
    b.dataset.id = o.id;
    b.textContent = o.text;
    b.addEventListener('click', () => answer(q, o.id, b));
    opts.append(b);
  }
}

function clampHealth(delta) {
  const rules = S.quiz.local_scoring;
  S.health = Math.max(rules.minimum_game_health, Math.min(rules.maximum_game_health, S.health + delta));
  const bar = $('panel').querySelector('.meter');
  if (bar) bar.outerHTML = healthMeter();
}

function answer(q, optionId, button) {
  const key = q.id;
  if (S.scored.has(key)) return;
  S.scored.add(key);
  const right = optionId === q.correct_option_id;
  $('panel').querySelectorAll('.option').forEach((b) => {
    b.disabled = true;
    if (b.dataset.id === q.correct_option_id) b.classList.add('correct');
  });
  if (!right) button.classList.add('picked');
  clampHealth((right ? q.correct_effect : q.wrong_effect).game_health_delta);
  const result = $('panel').querySelector('.q-result');
  const src = q.sources?.[0];
  result.hidden = false;
  result.innerHTML = `<p class="q-why"></p>${src ? `<a class="q-src" target="_blank" rel="noopener"></a>` : ''}`;
  result.querySelector('.q-why').textContent = q.explanation;
  if (src) { const a = result.querySelector('.q-src'); a.href = src.url; a.textContent = `Source: ${src.publisher}`; }
  const next = { label: 'Next question', kind: 'primary', run: () => { S.qIndex++; showQuiz(); } };
  if (right) {
    setTwin('happy');
    setPip('celebrating', 2400);
    say({ ask: 'Nice one!', after: 'Your twin feels great.', actions: [next] });
    return;
  }
  setTwin('sick');
  setPip('idle');
  document.body.classList.add('flash-answers');
  setTimeout(() => document.body.classList.remove('flash-answers'), 2400);
  say({
    lead: 'Oops! Your twin has a sniffle.',
    ask: 'Game health only.',
    after: "Your answers didn't change.",
    actions: [{ label: 'Help it recover', kind: 'primary', run: () => recover(q, next) }],
  });
}

function recover(q, next) {
  if (!S.reviewed.has(q.id)) {
    S.reviewed.add(q.id);
    clampHealth(q.review_effect.game_health_delta);
  }
  setTwin('recovering');
  setPip('celebrating', 2000);
  say({ ask: 'Thanks for reading!', after: 'Your twin feels better.', actions: [next] });
  setTimeout(() => S.twinMood === 'recovering' && setTwin('happy'), 3000);
}

// ---------- attract loop + takeover ----------

async function typeInto(text, token) {
  const input = $('say-input');
  input.value = '';
  for (const ch of text) {
    if (token !== attractToken) return false;
    input.value += ch;
    await sleep(reduceMotion.matches ? 0 : 55);
  }
  return token === attractToken;
}

async function runAttract() {
  const token = ++attractToken;
  S.attract = true;
  document.body.dataset.mode = `${S.mode} attract`;
  $('attract').hidden = false;
  $('say-input').disabled = true;
  resetGame();
  setScene('talk');
  await startTalk();
  const steps = S.replay.script.slice(1);
  for (const step of steps) {
    await pace(2600);
    if (token !== attractToken) return;
    if (!(await typeInto(step.text, token))) return;
    await pace(350);
    if (token !== attractToken) return;
    youSaid(step.text);
    $('say-input').value = '';
    if (S.mode === 'live') await act({ action: 'reply', text: step.text }, step.text);
    else { render(step.response, { kind: 'reply', text: step.text }); replayCursor++; }
  }
  await pace(5000);
  if (token === attractToken) runAttract();
}

function takeOver() {
  if (!S.attract) return;
  attractToken++;
  S.attract = false;
  $('attract').hidden = true;
  document.body.dataset.mode = S.mode;
  $('say-input').value = '';
  if (S.mode === 'replay') {
    // Without the server there is nothing real to type into, but the quiz
    // bank and its scoring are local.
    say({
      ask: 'Pip is offline right now.',
      after: 'You can still play the quiz.',
      actions: [{ label: 'Play the quiz', kind: 'primary', run: () => { resetGame(); go('quiz'); armIdle(); } }],
    });
    armIdle();
    return;
  }
  $('say-input').disabled = false;
  $('say-input').focus();
  resetGame();
  go('talk');
  armIdle();
}

function armIdle() {
  clearTimeout(idleTimer);
  if (!S.attract) idleTimer = setTimeout(runAttract, IDLE_MS);
}

function resetGame() {
  S.turn = null;
  S.tally = { understood: 0, again: 0, unasked: 0 };
  ['s-understood', 's-again', 's-unasked'].forEach((id) => { $(id).textContent = '0'; });
  S.health = 100;
  S.qIndex = 0;
  S.scored.clear();
  S.reviewed.clear();
  S.look = LOOKS[Math.floor(Math.random() * LOOKS.length)];
  S.twinMood = '';
  setTwin('happy');
  S.scene = '';
}

function restart() {
  resetGame();
  go('talk');
  armIdle();
}

async function goReplay(message) {
  S.mode = 'replay';
  document.body.dataset.mode = 'replay';
  $('mode-badge').textContent = 'Offline · recorded run';
  say({ ask: message });
  setTimeout(runAttract, 2500);
}

// ---------- boot ----------

async function boot() {
  drawScene();
  drawPip();
  S.replay = await fetch('replay.json').then((r) => r.json());
  S.mode = await detectMode();
  document.body.dataset.mode = S.mode;
  $('mode-badge').textContent = S.mode === 'live' ? 'Live · real parser' : 'Offline · recorded run';
  $('say').addEventListener('submit', (e) => { e.preventDefault(); reply($('say-input').value); });
  $('restart').addEventListener('click', restart);
  document.querySelectorAll('.steps [data-go]').forEach((b) => b.addEventListener('click', () => go(b.dataset.go)));
  const wake = (e) => {
    if (S.attract) {
      if (e.type === 'keydown' && (e.metaKey || e.ctrlKey || e.altKey)) return;
      if (e.key === ' ' || e.key === 'Enter') e.preventDefault(); // wake keys aren't answers
      takeOver();
    } else armIdle();
  };
  addEventListener('keydown', wake, true);
  addEventListener('pointerdown', wake, true);
  addEventListener('resize', layout);
  new ResizeObserver(layout).observe($('stage'));
  layout();
  runAttract();
}

boot();
