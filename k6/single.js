import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = 'http://postgrest.asusrogstrix.local';
const CASH_ACCOUNT = '10000000-0000-0000-0000-000000000000';
const REVENUE_ACCOUNT = '60000000-0000-0000-0000-000000000000';

export const options = {
  scenarios: {
    write: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '1m',
      preAllocatedVUs: 2,
      maxVUs: 2,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<50'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function() {
  const amount = Math.floor(Math.random() * 1000) + 1;
  const uniqueKey = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  
  const response = http.post(`${BASE_URL}/rpc/record_journal_entry_with_retries`,
    JSON.stringify({
      p_entry_date: new Date().toISOString().split('T')[0],
      p_description: `Test transaction ${amount}`,
      p_journal_lines: [
        {
          account_id: CASH_ACCOUNT,
          debit_amount: amount,
          credit_amount: 0,
          description: `Debit ${amount}`
        },
        {
          account_id: REVENUE_ACCOUNT,
          debit_amount: 0,
          credit_amount: amount,
          description: `Credit ${amount}`
        }
      ],
      p_reference_number: `TEST-${__VU}-${__ITER}`,
      p_created_by: 'k6_test',
      p_idempotency_key: uniqueKey
    }),
    {
      headers: { 'Content-Type': 'application/json' },
      timeout: '1s',
    }
  );

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 50ms': (r) => r.timings.duration < 50,
  });
}