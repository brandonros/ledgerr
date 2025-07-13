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
      executor: 'constant-arrival-rate',
      rate: 100, // Higher rate for reads since they're typically faster
      timeUnit: '1s',
      duration: '1m',
      preAllocatedVUs: 2,
      maxVUs: 2,
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
  
  // Mix of different query types
  const queryType = Math.random();
  let params = {};
  
  if (queryType < 0.7) {
    // 70% - Current balance queries (will use cache)
    params = {
      p_account_id: accountId
    };
  } else if (queryType < 0.9) {
    // 20% - Historical balance queries (will bypass cache)
    const daysBack = Math.floor(Math.random() * 30) + 1;
    const asOfDate = new Date();
    asOfDate.setDate(asOfDate.getDate() - daysBack);
    params = {
      p_account_id: accountId,
      p_as_of_date: asOfDate.toISOString().split('T')[0]
    };
  } else {
    // 10% - Force recalculate queries
    params = {
      p_account_id: accountId,
      p_force_recalculate: true
    };
  }
  
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