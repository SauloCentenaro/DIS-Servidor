import http from 'k6/http';
import { Counter } from 'k6/metrics';
import { config, target, payload, runtimeTags } from './configuration.js';
import { validate } from './validation.js';

const successfulRequests = new Counter('successful_requests');
const functionalFailures = new Counter('functional_failures');

export function performRequest() {
  const url = `${target.base_url.replace(/\/$/, '')}${target.endpoint}`;
  const params = {
    headers: target.headers || {},
    timeout: target.timeout || '30s',
    tags: { ...runtimeTags(), name: `${target.method} ${target.endpoint}` },
  };
  const method = (target.method || 'GET').toUpperCase();
  const response = http.request(method, url, ['GET', 'HEAD'].includes(method) ? null : payload, params);
  const ok = validate(response, target);
  if (ok) successfulRequests.add(1, config.tags); else functionalFailures.add(1, config.tags);
}
