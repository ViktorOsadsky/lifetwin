import {loadLab} from './model.mjs';

const $ = (id) => document.getElementById(id);
const numericKeys = [
  'age', 'bmi', 'sleep_hours', 'sedentary_min_day',
  'moderate_recreation_min_week', 'vigorous_recreation_min_week',
];
const categoryKeys = [
  'sex_nhanes', 'smoking_status', 'diabetes_diagnosed',
  'hypertension_diagnosed', 'general_health',
];
const svgNs = 'http://www.w3.org/2000/svg';
let lab;
let currentResult;

function profileFromForm() {
  const profile = {};
  for (const key of numericKeys) {
    const raw = $(key).value.trim();
    if (raw === '') throw new Error(`Enter ${key.replaceAll('_', ' ')}.`);
    profile[key] = Number(raw);
  }
  for (const key of categoryKeys) profile[key] = Number($(key).value);
  return profile;
}

function svgElement(tag, attributes, parent, value) {
  const node = document.createElementNS(svgNs, tag);
  for (const [name, val] of Object.entries(attributes)) node.setAttribute(name, String(val));
  if (value != null) node.textContent = value;
  parent.append(node);
  return node;
}

function renderChart(result) {
  const svg = $('chart');
  svg.replaceChildren();
  const left = 68, top = 20, right = 974, bottom = 355;
  const startAge = result.annual.points[0].age;
  const endAge = Math.max(result.annual.points.at(-1).age, result.fiveYear.points.at(-1).age);
  const x = (age) => left + (right - left) * (age - startAge) / Math.max(1, endAge - startAge);
  const y = (percent) => bottom - (bottom - top) * percent / 100;

  for (const percent of [0, 25, 50, 75, 100]) {
    svgElement('line', {x1: left, x2: right, y1: y(percent), y2: y(percent),
      class: percent === 50 ? 'fifty' : 'grid'}, svg);
    svgElement('text', {x: 3, y: y(percent) + 4, class: 'axis-label'}, svg, `${percent}%`);
  }
  for (let age = Math.ceil(startAge / 10) * 10; age <= endAge; age += 10) {
    svgElement('line', {x1: x(age), x2: x(age), y1: top, y2: bottom, class: 'grid'}, svg);
    svgElement('text', {x: x(age) - 11, y: bottom + 23, class: 'axis-label'}, svg, String(age));
  }
  for (const [age, label] of [[35, 'Trained ages begin'], [80, 'Trained ages end']]) {
    if (startAge < age && endAge >= age) {
      svgElement('line', {x1: x(age), x2: x(age), y1: top, y2: bottom, class: 'limit'}, svg);
      svgElement('text', {x: Math.min(x(age) + 6, right - 120), y: top + 15,
        class: 'axis-label'}, svg, label);
    }
  }
  svgElement('text', {x: (left + right) / 2 - 10, y: 403, class: 'axis-title'}, svg, 'AGE');

  function curve(points, style) {
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1], b = points[i];
      const line = svgElement('line', {
        x1: x(a.age), y1: y(a.survivalPercent), x2: x(b.age), y2: y(b.survivalPercent),
        class: `curve ${style}${b.extrapolated ? ' extrapolated' : ''}`,
      }, svg);
      svgElement('title', {}, line,
        `${style === 'annual' ? 'Yearly' : '5-year'}: age ${b.age}, ${b.survivalPercent.toFixed(2)}%${b.extrapolated ? ' (age extrapolation)' : ''}`);
    }
  }
  curve(result.fiveYear.points, 'block');
  curve(result.annual.points, 'annual');
}

function renderTable(result) {
  const rows = $('year-rows');
  rows.replaceChildren();
  const yearly = new Map(result.annual.points.map((point) => [point.age, point]));
  const blocks = new Map(result.fiveYear.points.map((point) => [point.age, point]));
  const ages = [...new Set([...yearly.keys(), ...blocks.keys()])].sort((a, b) => a - b);
  const display = (point) => point
    ? `${point.survivalPercent.toFixed(2)}%${point.extrapolated ? '*' : ''}` : '—';
  for (const age of ages) {
    const tr = document.createElement('tr');
    const a = yearly.get(age), b = blocks.get(age);
    for (const value of [age, display(a), display(b),
      a?.extrapolated || b?.extrapolated ? 'age extrapolation*' : 'age input 35–79']) {
      const td = document.createElement('td');
      td.textContent = String(value);
      tr.append(td);
    }
    rows.append(tr);
  }
}

function crossing(curve, valueId, noteId) {
  const age = curve.medianCrossingAge;
  $(valueId).textContent = age == null ? 'Not reached' : `Age ${age.toFixed(2)}${curve.medianCrossingExtrapolated ? '*' : ''}`;
  $(noteId).textContent = age == null ? 'within displayed range' :
    curve.medianCrossingExtrapolated ? 'unvalidated age extrapolation' : 'experimental median threshold';
}

function showError(message) {
  $('error-box').textContent = message;
  $('error-box').hidden = false;
  $('result-content').hidden = true;
  $('run-status').textContent = 'Input needed';
}

function renderWarnings(warnings) {
  const box = $('model-warnings');
  const list = $('warning-list');
  list.replaceChildren();
  box.hidden = warnings.length === 0;
  for (const warning of warnings) {
    const item = document.createElement('li');
    item.textContent = warning;
    list.append(item);
  }
}

function renderGap(result) {
  const byAge = new Map(result.fiveYear.points.map((point) => [point.age, point]));
  let gap = 0;
  let atAge = result.annual.points[0].age;
  for (const point of result.annual.points) {
    const other = byAge.get(point.age);
    if (!other) continue;
    const candidate = Math.abs(point.survivalPercent - other.survivalPercent);
    if (candidate > gap) {gap = candidate; atAge = point.age;}
  }
  $('gap-value').textContent = `${gap.toFixed(3)} percentage points`;
  $('gap-age').textContent = `largest difference at age ${atAge} in displayed range`;
}

function run() {
  if (!lab) return;
  try {
    const result = lab.assess(profileFromForm(), {
      includeExtrapolation: $('extrapolate').checked,
    });
    if (result.status !== 'available') {
      showError([result.message, ...result.issues].filter(Boolean).join(' '));
      currentResult = null;
      return;
    }
    currentResult = result;
    $('error-box').hidden = true;
    $('result-content').hidden = false;
    $('run-status').textContent = result.warnings.length
      ? 'Calculated locally · extrapolating' : 'Calculated locally';
    renderWarnings(result.warnings);
    $('hazard-value').textContent = `${result.neural.relativeHazardVsReference.toFixed(2)}×`;
    $('cox-value').textContent = `${(100 * result.current.survivalProbabilities[4]).toFixed(2)}%`;
    crossing(result.annual, 'annual-value', 'annual-note');
    crossing(result.fiveYear, 'five-value', 'five-note');
    $('neural-version').textContent = result.neural.modelVersion;
    $('cox-version').textContent = result.current.modelVersion;
    renderChart(result);
    renderGap(result);
    renderTable(result);
  } catch (error) {
    currentResult = null;
    showError(error.message || String(error));
  }
}

function downloadCsv() {
  if (!currentResult) return;
  const yearly = new Map(currentResult.annual.points.map((point) => [point.age, point]));
  const blocks = new Map(currentResult.fiveYear.points.map((point) => [point.age, point]));
  const ages = [...new Set([...yearly.keys(), ...blocks.keys()])].sort((a, b) => a - b);
  const lines = ['age,yearly_survival_percent,five_year_survival_percent,yearly_extrapolated,five_year_extrapolated'];
  for (const age of ages) {
    const a = yearly.get(age), b = blocks.get(age);
    lines.push([age, a?.survivalPercent ?? '', b?.survivalPercent ?? '',
      a?.extrapolated ?? '', b?.extrapolated ?? ''].join(','));
  }
  const address = URL.createObjectURL(new Blob([lines.join('\n')], {type: 'text/csv'}));
  const link = document.createElement('a');
  link.href = address;
  link.download = 'lifetwin-internal-projections.csv';
  link.click();
  setTimeout(() => URL.revokeObjectURL(address), 1000);
}

$('profile-form').addEventListener('submit', (event) => {event.preventDefault(); run();});
$('profile-form').addEventListener('reset', () => setTimeout(run, 0));
$('extrapolate').addEventListener('change', run);
$('download-csv').addEventListener('click', downloadCsv);

try {
  lab = await loadLab();
  run();
} catch (error) {
  showError(`Could not load local model files. Serve this folder with a local HTTP server. ${error.message || error}`);
}
