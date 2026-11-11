import { check } from 'k6';

function pathValue(value, path) {
  return path.split('.').reduce((current, key) => current == null ? undefined : current[key], value);
}

export function validate(response, target) {
  const checks = {
    'status is expected': r => r.status === Number(target.expected_status),
    'body is not empty': r => (r.body || '').length >= Number(target.minimum_response_bytes || 1),
  };
  if (target.maximum_duration_ms) {
    checks['duration is acceptable'] = r => r.timings.duration <= Number(target.maximum_duration_ms);
  }

  const needsJson = target.full_validation || (target.required_fields || []).length || Object.keys(target.array_lengths || {}).length || Object.keys(target.response_equals || {}).length;
  if (!needsJson) return check(response, checks);

  let parsed;
  try { parsed = response.json(); } catch (_) { parsed = undefined; }
  checks['body is valid JSON'] = () => parsed !== undefined;
  for (const field of target.required_fields || []) {
    checks[`field exists: ${field}`] = () => pathValue(parsed, field) !== undefined;
  }
  if (target.full_validation) {
    for (const [field, length] of Object.entries(target.array_lengths || {})) {
      checks[`array length: ${field}`] = () => Array.isArray(pathValue(parsed, field)) && pathValue(parsed, field).length === Number(length);
    }
    for (const [field, expected] of Object.entries(target.response_equals || {})) {
      checks[`value equals: ${field}`] = () => JSON.stringify(pathValue(parsed, field)) === JSON.stringify(expected);
    }
  }
  return check(response, checks);
}
