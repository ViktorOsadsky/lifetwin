import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createLab} from '../model.mjs';

const url = (name) => new URL(name, import.meta.url);
const json = (name) => JSON.parse(readFileSync(url(name), 'utf8'));
const lab = createLab({
  cox: json('../assets/cox.json'),
  neural: json('../assets/neural.json'),
  referenceBytes: readFileSync(url('../assets/support_reference.f64')),
});
const coxVectors = json('./cox_vectors.json');
const neuralVectors = json('./neural_vectors.json');
const close = (actual, expected, tolerance = 1e-8) =>
  assert.ok(Math.abs(actual - expected) < tolerance, `${actual} != ${expected}`);

test('browser Cox arithmetic matches exported Python vectors', () => {
  for (const vector of coxVectors) {
    const result = lab.assess(vector.profile);
    assert.equal(result.status, 'available');
    close(result.current.logRelativeHazard, vector.log_relative_hazard_score, 1e-10);
    for (let i = 1; i <= 5; i++) {
      close(result.current.survivalProbabilities[i - 1],
        vector.survival_probabilities[String(i)], 1e-10);
    }
  }
});

test('browser neural arithmetic matches exported Keras vectors', () => {
  for (const vector of neuralVectors) {
    const result = lab.assess(vector.profile);
    assert.equal(result.status, 'available');
    close(result.neural.logRelativeHazard, vector.log_relative_hazard, 1e-5);
  }
  close(lab.assess(neuralVectors[0].profile).neural.relativeHazardVsReference, 1);
});

test('both age-stepping methods match the Dart reference and mark extrapolation', () => {
  const result = lab.assess(neuralVectors[1].profile);
  assert.equal(result.status, 'available');
  close(result.annual.points[1].survivalPercent,
    result.current.survivalProbabilities[0] * 100);
  close(result.fiveYear.points[5].survivalPercent,
    result.current.survivalProbabilities[4] * 100);
  close(result.annual.medianCrossingAge, 103.07835601243912, 1e-8);
  close(result.fiveYear.medianCrossingAge, 103.13947364142528, 1e-8);
  assert.equal(result.annual.medianCrossingExtrapolated, true);
  assert.equal(result.fiveYear.medianCrossingExtrapolated, true);
  for (const curve of [result.annual, result.fiveYear]) {
    for (let i = 1; i < curve.points.length; i++) {
      assert.ok(curve.points[i].survivalPercent <= curve.points[i - 1].survivalPercent);
    }
  }
  const supported = lab.assess(neuralVectors[1].profile, {includeExtrapolation: false});
  assert.equal(supported.annual.points.at(-1).age, 80);
  assert.equal(supported.annual.medianCrossingAge, null);
});

test('missing and unsupported profiles produce no invented outputs', () => {
  const profile = neuralVectors[1].profile;
  assert.equal(lab.assess({...profile, general_health: null}).status, 'missing_inputs');
  assert.equal(lab.assess({...profile, age: 85}).status, 'unsupported_age');
  assert.equal(lab.assess({...profile, bmi: 60}).status, 'unsupported_profile');
  assert.throws(() => lab.assess({...profile, sleep_hours: 30}), /sleep_hours/);
});
