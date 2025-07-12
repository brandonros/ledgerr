import http from 'k6/http';
import { check } from 'k6';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Test configuration
export const options = {
  scenarios: {
    // 70% reads (balance checks) - 70 TPS
    balance_reads: {
      executor: 'constant-arrival-rate',
      rate: 70,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 10,
      maxVUs: 20,
      exec: 'getBalance',
    },
    // 30% writes (transactions) - 30 TPS
    transaction_writes: {
      executor: 'constant-arrival-rate',
      rate: 30,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 5,
      maxVUs: 10,
      exec: 'createTransaction',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests under 500ms
    http_req_failed: ['rate<0.1'],    // Less than 10% failures
  },
};

const BASE_URL = 'http://localhost:3000';

// Test accounts (use your actual test account IDs)
const ACCOUNTS = [
  '10000000-0000-0000-0000-000000000000', // Cash
  '20000000-0000-0000-0000-000000000000', // Receivable  
  '50000000-0000-0000-0000-000000000000', // Capital
  '60000000-0000-0000-0000-000000000000', // Revenue
];

// Get random account balance
export function getBalance() {
  const accountId = ACCOUNTS[Math.floor(Math.random() * ACCOUNTS.length)];
  
  const response = http.post(`${BASE_URL}/rpc/get_account_balance`, 
    JSON.stringify({
      p_account_id: accountId
    }), 
    {
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/vnd.pgrst.object+json',
      },
    }
  );

  check(response, {
    'balance check status is 200': (r) => r.status === 200,
    'balance response time < 200ms': (r) => r.timings.duration < 200,
  });
}

// Create random transaction
export function createTransaction() {
  const amount = Math.floor(Math.random() * 1000) + 1; // $1-$1000
  const runId = Date.now();
  const uniqueKey = `LOAD-${runId}-${randomString(8)}-${__VU}-${__ITER}`;
  
  // Random debit/credit pair
  const debitAccount = ACCOUNTS[0]; // Cash
  const creditAccount = ACCOUNTS[Math.floor(Math.random() * (ACCOUNTS.length - 1)) + 1];
  
  const response = http.post(`${BASE_URL}/rpc/record_journal_entry`,
    JSON.stringify({
      p_entry_date: new Date().toISOString().split('T')[0],
      p_description: `Load test transaction ${amount}`,
      p_journal_lines: [
        {
          account_id: debitAccount,
          debit_amount: amount,
          credit_amount: 0,
          description: `Debit ${amount}`
        },
        {
          account_id: creditAccount, 
          debit_amount: 0,
          credit_amount: amount,
          description: `Credit ${amount}`
        }
      ],
      p_reference_number: `LOAD-${__VU}-${__ITER}`,
      p_created_by: 'k6_load_test',
      p_idempotency_key: uniqueKey
    }),
    {
      headers: {
        'Content-Type': 'application/json',
      },
    }
  );

  check(response, {
    'transaction status is 200': (r) => r.status === 200,
    'transaction response time < 1000ms': (r) => r.timings.duration < 1000,
    'transaction created': (r) => r.body && r.body.length > 0,
  });

  // Handle idempotency conflicts (409s are OK for load testing)
  if (response.status === 409) {
    console.log(`Idempotency conflict for key: ${uniqueKey}`);
  }
}