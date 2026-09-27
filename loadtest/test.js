import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const success = new Rate('business_success');
export const options = {
  stages: [
    { duration: '30s', target: 2 },
    { duration: '90s', target: 10 },
    { duration: '120s', target: 20 },
    { duration: '60s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    business_success: ['rate>0.99'],
    http_req_duration: ['p(95)<3000'],
    // Fast connection failures must not make successful-request latency look good.
    'http_req_duration{expected_response:true}': ['p(95)<3000'],
  },
};

export default function () {
  // Login hashes/verifies a password and exercises a real API and the database.
  const response = http.post(`${__ENV.BASE_URL}/users/login`,
    JSON.stringify({ email: __ENV.TEST_EMAIL, password: __ENV.TEST_PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } });
  success.add(check(response, { 'login succeeds': r => r.status === 200 }));
  sleep(0.5);
}
