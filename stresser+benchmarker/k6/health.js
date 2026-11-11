import http from 'k6/http';
import { check } from 'k6';

export const options = { vus: 1, iterations: 1, thresholds: { checks: ['rate==1'] }, insecureSkipTLSVerify: __ENV.INSECURE_TLS === 'true' };
export default function () {
  const response = http.request(__ENV.HEALTH_METHOD || 'GET', __ENV.HEALTH_URL, __ENV.HEALTH_BODY || null, {
    headers: JSON.parse(__ENV.HEALTH_HEADERS || '{}'), timeout: __ENV.HEALTH_TIMEOUT || '10s'
  });
  check(response, { 'target is ready': r => r.status === Number(__ENV.EXPECTED_STATUS || 200) });
}
