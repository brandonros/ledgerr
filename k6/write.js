import http from 'k6/http';
import { check } from 'k6';

// ============================================
// SIMPLE CONFIGURATION
// ============================================
const TARGET_WRITE_TPS = 25;        // Start low and increase to find limit
const TEST_DURATION = '60s';        // How long to run
const RAMP_UP_TIME = '10s';         // Time to reach target TPS

const BASE_URL = 'http://postgrest.asusrogstrix.local';

// Just two accounts for simplicity
const CASH_ACCOUNT = '10000000-0000-0000-0000-000000000000';
const REVENUE_ACCOUNT = '60000000-0000-0000-0000-000000000000';

export const options = {
  scenarios: {
    simple_writes: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 10,
      maxVUs: 50,
      stages: [
        { duration: RAMP_UP_TIME, target: TARGET_WRITE_TPS },
        { duration: TEST_DURATION, target: TARGET_WRITE_TPS },
      ],
      exec: 'writeTransaction',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 500ms threshold
    http_req_failed: ['rate<0.1'],     // 10% error rate threshold
    checks: ['rate>0.9'],              // 90% success rate
  },
};

export function writeTransaction() {
  const amount = Math.floor(Math.random() * 1000) + 1;
  const uniqueKey = `TEST-${Date.now()}-${Math.random().toString(36).substr(2, 9)}-${__VU}-${__ITER}`;
  
  const response = http.post(`${BASE_URL}/rpc/record_journal_entry_with_retries`,
    JSON.stringify({
      p_entry_date: new Date().toISOString().split('T')[0],
      p_description: `Simple test transaction ${amount}`,
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
      p_created_by: 'k6_simple_test',
      p_idempotency_key: uniqueKey
    }),
    {
      headers: {
        'Content-Type': 'application/json',
      },
      timeout: '10s',
    }
  );

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'transaction created': (r) => r.body && r.body.length > 0,
  });

  // Enhanced error logging
  if (!success || response.status >= 400) {
    console.error(`❌ Transaction failed:`);
    console.error(`   Status: ${response.status}`);
    console.error(`   Duration: ${response.timings.duration}ms`);
    console.error(`   VU: ${__VU}, Iteration: ${__ITER}`);
    console.error(`   URL: ${response.url}`);
    
    // Log response body for any error status
    if (response.body) {
      console.error(`   Response Body: ${response.body}`);
    }
    
    // For 400 errors specifically, you could also throw to stop the VU
    if (response.status === 400) {
      console.error(`   🚨 Bad Request - throwing error to stop VU`);
      throw new Error(`HTTP 400 Bad Request: ${response.body}`);
    }
  }

  // Optional: Log successful transactions occasionally for debugging
  if (success && __ITER % 100 === 0) {
    console.log(`✅ Transaction ${__ITER} successful (VU ${__VU})`);
  }
}

// Quick test to verify setup
export function setup() {
  console.log(`Starting simple write test:`);
  console.log(`Target TPS: ${TARGET_WRITE_TPS}`);
  console.log(`Test duration: ${TEST_DURATION}`);
  console.log(`Cash Account: ${CASH_ACCOUNT}`);
  console.log(`Revenue Account: ${REVENUE_ACCOUNT}`);
}