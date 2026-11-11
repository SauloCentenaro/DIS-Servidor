import exec from 'k6/execution';

const configPath = __ENV.CONFIG_PATH || '/results/effective-config.yaml';
export const config = JSON.parse(open(configPath));
export const target = config.target;
export const experiment = config.experiment;
export const payloadPath = __ENV.PAYLOAD_PATH || target.payload;
export const payload = open(`/workspace/${payloadPath}`);

function scenarioDefinition() {
  const e = experiment;
  const common = { exec: 'runRequest', tags: config.tags };
  if (e.executor === 'shared-iterations') {
    return { ...common, executor: e.executor, vus: e.vus, iterations: e.iterations, maxDuration: e.max_duration || '10m' };
  }
  if (e.executor === 'constant-vus') {
    return { ...common, executor: e.executor, vus: e.vus, duration: e.duration };
  }
  if (e.executor === 'constant-arrival-rate') {
    return { ...common, executor: e.executor, rate: e.rate, timeUnit: e.time_unit || '1s', duration: e.duration,
      preAllocatedVUs: e.preallocated_vus, maxVUs: e.max_vus };
  }
  if (e.executor === 'ramping-arrival-rate') {
    return { ...common, executor: e.executor, startRate: e.start_rate || 0, timeUnit: e.time_unit || '1s',
      preAllocatedVUs: e.preallocated_vus, maxVUs: e.max_vus, stages: e.stages };
  }
  throw new Error(`Unsupported executor: ${e.executor}`);
}

export function buildOptions() {
  return {
    scenarios: { measured: scenarioDefinition() },
    thresholds: config.thresholds,
    insecureSkipTLSVerify: Boolean(target.insecure_tls),
    discardResponseBodies: false,
    userAgent: `benchmark-lab/${config.run_id}`,
    systemTags: ['status', 'method', 'url', 'name', 'scenario', 'expected_response'],
    summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
    setupTimeout: '60s',
    teardownTimeout: '60s',
  };
}

export function runtimeTags() {
  return {
    ...config.tags,
    vu: String(exec.vu.idInTest),
  };
}
