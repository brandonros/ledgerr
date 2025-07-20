import http from 'k6/http';
import { check, sleep } from 'k6';

//const BASE_URL = 'http://postgrest.asusrogstrix.local';
const BASE_URL = 'http://localhost:3000';
const CASH_ACCOUNT = '10000000-0000-0000-0000-000000000000';
const REVENUE_ACCOUNT = '60000000-0000-0000-0000-000000000000';

export const options = {
  scenarios: {
    write: {
      executor: 'ramping-arrival-rate',
      stages: [
        { duration: '15s', target: 10 },
        { duration: '15s', target: 25 },
        { duration: '15s', target: 50 },
        { duration: '15s', target: 75 },
        { duration: '15s', target: 100 },
        { duration: '15s', target: 125 },
        { duration: '15s', target: 150 },
        { duration: '15s', target: 175 },
        { duration: '15s', target: 200 },
        { duration: '5m', target: 200 },
      ],
      preAllocatedVUs: 2,
      maxVUs: 100,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<200'],
    'http_req_failed': ['rate<0.05'],
    'checks{check:successful_transaction}': ['rate>0.95'],
    'checks{check:response_time_ok}': ['rate>0.8'],
  },
};

function isSerializationConflict(response) {
  if (response.status !== 400) return false;
  
  try {
    const body = JSON.parse(response.body);
    return body.code === 'P0001';
  } catch (e) {
    return false;
  }
}

export default function() {
  const amount = Math.floor(Math.random() * 1000) + 1;
  const uniqueKey = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  
  const payload = {
    p_entry_date: new Date().toISOString().split('T')[0],
    p_description: `Test transaction ${amount}`,
    p_debit_line: {
      account_id: CASH_ACCOUNT,
      debit_amount: amount,
      credit_amount: 0,
      description: `Debit ${amount}`
    },
    p_credit_line: {
      account_id: REVENUE_ACCOUNT,
      debit_amount: 0,
      credit_amount: amount,
      description: `Credit ${amount}`
    },
    p_reference_number: `TEST-${__VU}-${__ITER}`,
    p_created_by: 'k6_test',
    p_idempotency_key: uniqueKey,
  };
  
  // Retry logic for serialization conflicts
  let response;
  let retryCount = 0;
  const maxRetries = 10;
  
  do {
    response = http.post(`${BASE_URL}/rpc/record_journal_entry`,
      JSON.stringify(payload),
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: '10s',
      }
    );
    
    // Handle serialization conflicts with retry
    if (isSerializationConflict(response) && retryCount < maxRetries) {
      //console.log(`🔄 RETRY ${retryCount + 1}/${maxRetries} - VU: ${__VU}, Serialization conflict`);
      retryCount++;
      // Random backoff between 10-50ms
      const backoff = Math.floor(Math.random() * 40) + 10;
      sleep(backoff / 1000);
      continue;
    }
    
    break; // Exit retry loop
  } while (retryCount <= maxRetries);

  // Determine if transaction was successful
  const isSuccess = response.status === 200;
  const isConflict = isSerializationConflict(response);
  
  // Log results
  if (isSuccess) {
    //console.log(`✅ SUCCESS - VU: ${__VU}, Entry ID: ${response.body.replace(/"/g, '')}, Duration: ${response.timings.duration}ms`);
  } else if (isConflict) {
    console.log(`⚠️  SERIALIZATION_CONFLICT - VU: ${__VU}, Retries: ${retryCount}`);
  } else {
    console.log(`❌ ERROR - VU: ${__VU}, Status: ${response.status}, Body: ${response.body}`);
  }
  
  // Simplified checks
  check(response, {
    'successful_transaction': () => isSuccess,
    'response_time_ok': (r) => r.timings.duration < 100,
  });
}
