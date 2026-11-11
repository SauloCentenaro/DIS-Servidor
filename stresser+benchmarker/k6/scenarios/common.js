import { buildOptions, config } from '../lib/configuration.js';
import { performRequest } from '../lib/request.js';

export const options = buildOptions();
export function runRequest() { performRequest(); }

export function handleSummary(data) {
  const checks = data.metrics.checks && data.metrics.checks.values;
  const summary = {
    run_id: config.run_id,
    target: config.target_name,
    experiment: config.experiment_name,
    root_group: data.root_group,
    metrics: data.metrics,
    state: data.state,
  };
  const checkReport = {
    run_id: config.run_id,
    passes: checks ? checks.passes : 0,
    fails: checks ? checks.fails : 0,
    success_rate: checks && checks.passes + checks.fails > 0 ? checks.passes / (checks.passes + checks.fails) : null,
    threshold_failures: Object.fromEntries(Object.entries(data.metrics)
      .filter(([, metric]) => metric.thresholds && Object.values(metric.thresholds).some(v => !v.ok))
      .map(([name, metric]) => [name, metric.thresholds])),
  };
  return {
    stdout: textSummary(data),
    [`${__ENV.RESULT_DIR}/k6-summary.json`]: JSON.stringify(summary, null, 2),
    [`${__ENV.RESULT_DIR}/checks.json`]: JSON.stringify(checkReport, null, 2),
  };
}

function textSummary(data) {
  const m = data.metrics.http_req_duration;
  const reqs = data.metrics.http_reqs;
  const failed = data.metrics.http_req_failed;
  return `\nBenchmark ${config.run_id}\nrequests: ${reqs ? reqs.values.count : 0}\nRPS: ${reqs ? reqs.values.rate.toFixed(2) : 0}\nlatency p95: ${m ? m.values['p(95)'].toFixed(2) : 0} ms\nfailed rate: ${failed ? failed.values.rate.toFixed(4) : 0}\n`;
}
