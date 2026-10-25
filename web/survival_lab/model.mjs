/** Local, dependency-free inference for the internal LifeTwin model tester. */

const COX_COLUMNS = 17;

export async function loadLab() {
  const paths = ['cox.json', 'neural.json', 'support_reference.f64'];
  const responses = await Promise.all(paths.map((name) =>
    fetch(new URL(`./assets/${name}`, import.meta.url))));
  for (const response of responses) {
    if (!response.ok) throw new Error(`Could not load ${response.url}: HTTP ${response.status}`);
  }
  const [cox, neural, referenceBytes] = await Promise.all([
    responses[0].json(), responses[1].json(), responses[2].arrayBuffer(),
  ]);
  return createLab({cox, neural, referenceBytes});
}

export function createLab({cox, neural, referenceBytes}) {
  const bytes = referenceBytes instanceof Uint8Array
    ? referenceBytes
    : new Uint8Array(referenceBytes);
  if (bytes.byteLength % (COX_COLUMNS * 8) !== 0 || bytes.byteLength === 0) {
    throw new Error('Malformed Cox support reference');
  }
  const reference = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const referenceRows = bytes.byteLength / (COX_COLUMNS * 8);

  function validate(profile) {
    const required = cox.input_features;
    const extra = Object.keys(profile).filter((key) => !required.includes(key));
    if (extra.length) throw new Error(`Unknown inputs: ${extra.join(', ')}`);
    const missing = required.filter((key) => profile[key] === '' || profile[key] == null);
    if (missing.length) return {status: 'missing_inputs', message: `Add: ${missing.join(', ')}`};
    for (const key of required) {
      if (typeof profile[key] !== 'number' || !Number.isFinite(profile[key])) {
        throw new Error(`${key} must be a finite number`);
      }
    }
    for (const [key, [lo, hi]] of Object.entries(cox.numeric_bounds)) {
      // Age beyond 79 has its own supported-range message below.
      if (key !== 'age' && (profile[key] < lo || profile[key] > hi)) {
        throw new Error(`${key} must be between ${lo} and ${hi}`);
      }
    }
    for (const [key, allowed] of Object.entries(cox.categorical_allowed)) {
      if (!allowed.includes(profile[key])) throw new Error(`${key} has an unsupported category`);
    }
    const activity = profile.vigorous_recreation_min_week + profile.moderate_recreation_min_week;
    if (profile.sleep_hours * 60 + profile.sedentary_min_day > 1440 ||
        activity > 10080 ||
        profile.sleep_hours * 60 + profile.sedentary_min_day + activity / 7 > 1440) {
      throw new Error('Sleep, sitting and recreation exceed available time');
    }
    if (!Number.isInteger(profile.age)) throw new Error('Age must be in completed years');
    if (profile.age < cox.age_range[0] || profile.age > cox.age_range[1]) {
      return {status: 'unsupported_age', message: 'Current estimates support ages 35–79.'};
    }
    return {status: 'valid'};
  }

  function encodeCox(p) {
    return [
      (p.age - 55) / 10,
      Math.max(23 - p.bmi, 0) / 5,
      Math.max(p.bmi - 27, 0) / 5,
      Math.max(7 - p.sleep_hours, 0),
      Math.max(p.sleep_hours - 8, 0),
      Math.log1p(p.vigorous_recreation_min_week) / Math.log(76),
      Math.log1p(p.moderate_recreation_min_week) / Math.log(151),
      (p.sedentary_min_day - 360) / 120,
      p.sex_nhanes === 2 ? 1 : 0,
      p.smoking_status === 1 ? 1 : 0,
      p.smoking_status === 2 ? 1 : 0,
      p.diabetes_diagnosed,
      p.hypertension_diagnosed,
      ...[2, 3, 4, 5].map((level) => p.general_health === level ? 1 : 0),
    ];
  }

  function coxScore(profile) {
    const encoded = encodeCox(profile);
    let score = 0;
    for (let i = 0; i < COX_COLUMNS; i++) {
      score += (encoded[i] - cox.feature_center[i]) * cox.coefficients[i];
    }
    return {encoded, score};
  }

  function supportIssues(profile, encoded) {
    const issues = [];
    for (const [key, [lo, hi]] of Object.entries(cox.numeric_support_1_99pct)) {
      if (profile[key] < lo || profile[key] > hi) {
        issues.push(`${key} is outside the training 1st–99th percentile range`);
      }
    }
    const distances = new Float64Array(referenceRows);
    for (let row = 0; row < referenceRows; row++) {
      let squared = 0;
      for (let col = 0; col < COX_COLUMNS; col++) {
        const stored = reference.getFloat64((row * COX_COLUMNS + col) * 8, true);
        squared += (stored - encoded[col]) ** 2;
      }
      distances[row] = Math.sqrt(squared);
    }
    distances.sort();
    if (distances[cox.neighbor_count - 1] > cox.neighbor_distance_cutoff) {
      issues.push('The input combination has few nearby training profiles');
    }
    return issues;
  }

  function survivalAt(profile, years) {
    const {score} = coxScore(profile);
    return cox.baseline_survival[years - 1] ** Math.exp(Math.max(-40, Math.min(40, score)));
  }

  function predictCox(profile) {
    const validity = validate(profile);
    if (validity.status !== 'valid') return validity;
    const {encoded, score} = coxScore(profile);
    const issues = supportIssues(profile, encoded);
    if (issues.length) {
      return {status: 'unsupported_profile', message: 'No supported current estimate for this input combination.', issues};
    }
    return {
      status: 'available', modelVersion: cox.model_version, logRelativeHazard: score,
      survivalProbabilities: cox.horizons_years.map((years) => survivalAt(profile, years)),
    };
  }

  function predictNeural(profile) {
    const values = [];
    for (const key of neural.numeric_features) values.push(profile[key]);
    for (let i = 0; i < neural.numeric_means.length; i++) {
      values[i] = ((i < neural.numeric_features.length ? values[i] : 0) -
        neural.numeric_means[i]) / neural.numeric_scales[i];
    }
    for (let i = 0; i < neural.categorical_features.length; i++) {
      const actual = profile[neural.categorical_features[i]];
      for (const level of neural.categorical_levels[i]) values.push(actual === level ? 1 : 0);
    }
    let activations = values;
    neural.layers.forEach((layer, index) => {
      const next = layer.bias.map((bias, out) => {
        let sum = bias;
        for (let input = 0; input < activations.length; input++) {
          sum += activations[input] * layer.kernel[input][out];
        }
        return index === neural.layers.length - 1 ? sum : Math.max(0, sum);
      });
      activations = next;
    });
    const logRelativeHazard = activations[0];
    return {
      modelVersion: neural.model_version,
      logRelativeHazard,
      relativeHazardVsReference: Math.exp(logRelativeHazard - neural.reference_log_hazard),
      referenceProfile: neural.reference_profile,
    };
  }

  function project(profile, step, maximumAge, includeExtrapolation) {
    let cumulative = 1;
    let crossing = null;
    let crossingExtrapolated = false;
    const points = [{age: profile.age, survivalPercent: 100, extrapolated: false}];
    for (let blockAge = profile.age; blockAge < maximumAge; blockAge += step) {
      if (blockAge > 79 && !includeExtrapolation) break;
      const future = {...profile, age: blockAge};
      const blockStart = cumulative;
      for (let years = 1; years <= Math.min(step, maximumAge - blockAge); years++) {
        const next = blockStart * survivalAt(future, years);
        const age = blockAge + years;
        if (crossing === null && cumulative > .5 && next <= .5) {
          crossing = age - 1 + (cumulative - .5) / (cumulative - next);
          crossingExtrapolated = blockAge > 79;
        }
        cumulative = next;
        points.push({age, survivalPercent: 100 * cumulative, extrapolated: blockAge > 79});
      }
    }
    return {step, points, medianCrossingAge: crossing, medianCrossingExtrapolated: crossingExtrapolated};
  }

  return {
    coxVersion: cox.model_version,
    neuralVersion: neural.model_version,
    assess(profile, {includeExtrapolation = true, maximumAge = 110} = {}) {
      const current = predictCox(profile);
      if (current.status !== 'available') return {status: current.status, message: current.message, issues: current.issues ?? []};
      if (maximumAge <= profile.age || maximumAge > 110) throw new Error('Maximum age must be above current age and at most 110');
      return {
        status: 'available', neural: predictNeural(profile), current,
        annual: project(profile, 1, maximumAge, includeExtrapolation),
        fiveYear: project(profile, 5, maximumAge, includeExtrapolation),
      };
    },
  };
}
