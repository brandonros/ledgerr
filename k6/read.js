import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = 'http://postgrest.asusrogstrix.local';
const CASH_ACCOUNT = '10000000-0000-0000-0000-000000000000';
const REVENUE_ACCOUNT = '60000000-0000-0000-0000-000000000000';

// Add more accounts if you have them for varied testing
const ACCOUNTS = [
  CASH_ACCOUNT,
  REVENUE_ACCOUNT,
  // Add more account IDs here if available
];

export const options = {
  scenarios: {
    sustained: {
      executor: 'ramping-arrival-rate',
      stages: [
        { duration: '10s', target: 5 },    // Gentle warmup
        { duration: '20s', target: 50 },   // Ramp to target
        { duration: '30s', target: 50 },   // Hold at 50 RPS for 45 seconds
      ],
      preAllocatedVUs: 10,
      maxVUs: 10,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<30'], // Reads should be faster than writes
    http_req_failed: ['rate<0.01'],
  },
};

export default function() {
  // Randomly select an account to query
  const accountId = ACCOUNTS[Math.floor(Math.random() * ACCOUNTS.length)];
  
  // 100% - Current balance queries (will use cache)
  const params = {
    p_account_id: accountId
  };
  
  const response = http.post(`${BASE_URL}/rpc/get_account_balance`,
    JSON.stringify(params),
    {
      headers: { 'Content-Type': 'application/json' },
      timeout: '1s',
    }
  );

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 30ms': (r) => r.timings.duration < 30,
    'has account_balance': (r) => {
      try {
        const data = JSON.parse(r.body);
        return data && typeof data.account_balance !== 'undefined';
      } catch (e) {
        return false;
      }
    },
    'has transaction_count': (r) => {
      try {
        const data = JSON.parse(r.body);
        return data && typeof data.transaction_count !== 'undefined';
      } catch (e) {
        return false;
      }
    }
  });
}