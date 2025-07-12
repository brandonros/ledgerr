import http from 'k6/http';
import { check, sleep } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

// DEMO CONFIGURATION - Quick 60 second tests for each scenario
export const options = {
  scenarios: {
    // Scenario 1: Pure transaction creation TPS (distributed across accounts)
    transaction_creation: {
      executor: 'constant-arrival-rate',
      rate: 50, // Start with 50 TPS, increase as needed
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 20,
      maxVUs: 50,
      tags: { scenario: 'create_transactions' },
      exec: 'createTransactions',
    },
    
    // Scenario 2: Pure balance query TPS  
    balance_queries: {
      executor: 'constant-arrival-rate',
      rate: 100, // Start with 100 TPS, increase as needed
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 10,
      maxVUs: 30,
      tags: { scenario: 'query_balances' },
      exec: 'queryBalances',
      startTime: '70s', // Start after transaction test
    },
    
    // Scenario 3: SINGLE HOT ACCOUNT - Original test for comparison
    single_account_hammer: {
      executor: 'constant-arrival-rate',
      rate: 25, // Start conservative - this is the breaking point test
      timeUnit: '1s',
      duration: '90s', // Longer to see sustained locking behavior
      preAllocatedVUs: 30,
      maxVUs: 100,
      tags: { scenario: 'single_hot_account' },
      exec: 'hammerSingleHotAccount',
      startTime: '140s',
    },
    
    // Scenario 4: 🔥 MULTI-HOT ACCOUNT NIGHTMARE - The real banking locking test
    multi_hot_accounts: {
      executor: 'constant-arrival-rate',
      rate: 100, // 100 TPS across 10 hot accounts = 10 TPS per hot account
      timeUnit: '1s',
      duration: '120s', // Longer test to see sustained multi-account contention
      preAllocatedVUs: 50,
      maxVUs: 150, // Allow more VUs for this intense test
      tags: { scenario: 'multi_hot_accounts' },
      exec: 'hammerMultipleHotAccounts',
      startTime: '240s',
    },
    
    // Scenario 5: Mixed workload (realistic production)
    mixed_workload: {
      executor: 'constant-arrival-rate',
      rate: 75, // Mixed TPS
      timeUnit: '1s', 
      duration: '60s',
      preAllocatedVUs: 15,
      maxVUs: 40,
      tags: { scenario: 'mixed_workload' },
      exec: 'mixedWorkload',
      startTime: '370s', // Start after all locking tests
    }
  },
  
  thresholds: {
    // Clear success criteria for demo
    'http_req_duration{scenario:create_transactions}': ['p(95)<1000'],
    'http_req_duration{scenario:query_balances}': ['p(95)<200'],
    'http_req_duration{scenario:mixed_workload}': ['p(95)<500'],
    
    // Single hot account locking performance
    'http_req_duration{scenario:single_hot_account}': ['p(95)<2000'],
    'http_req_duration{scenario:single_hot_account}': ['p(99)<5000'],
    'http_req_failed{scenario:single_hot_account}': ['rate<0.05'],
    
    // 🔥 THE CRITICAL MULTI-HOT ACCOUNT THRESHOLDS
    'http_req_duration{scenario:multi_hot_accounts}': ['p(95)<3000'], // More lenient for multi-contention
    'http_req_duration{scenario:multi_hot_accounts}': ['p(99)<8000'], // Watch for cascading lock failures
    'http_req_failed{scenario:multi_hot_accounts}': ['rate<0.10'], // 10% error tolerance for extreme scenario
    
    'http_req_failed': ['rate<0.02'], // 2% errors overall (more lenient due to locking tests)
  },
};

const BASE_URL = 'http://localhost:3000';
const HEADERS = { 'Content-Type': 'application/json' };

// Pre-created accounts for realistic testing
const ACCOUNT_POOL = [];
const POPULAR_ACCOUNTS = []; // Simulate high-volume accounts
const HOT_ACCOUNTS = []; // Multiple hot accounts for locking tests

// Setup function - create proper scale account pool
export function setup() {
console.log('Setting up test accounts at scale...');

// Clear the global arrays first
ACCOUNT_POOL.length = 0;
POPULAR_ACCOUNTS.length = 0;
HOT_ACCOUNTS.length = 0;

// Create 10,000 regular accounts (proper scale)
for (let i = 0; i < 10000; i++) {
    const accountId = uuidv4();
    const accountType = ['ASSET', 'LIABILITY', 'REVENUE', 'EXPENSE'][i % 4];
    
    const response = http.post(`${BASE_URL}/rpc/create_account`, JSON.stringify({
    p_account_id: accountId,
    p_account_code: `TEST-${i.toString().padStart(5, '0')}`,
    p_account_name: `Test Account ${i}`,
    p_account_type: accountType,
    p_parent_account_id: null
    }), { headers: HEADERS });
    
    if (response.status === 200) {
    ACCOUNT_POOL.push(accountId);
    
    // Mark first 100 as "popular" accounts 
    if (i < 100) {
        POPULAR_ACCOUNTS.push(accountId);
    }
    } else {
    console.log(`Failed to create account ${i}: ${response.status} - ${response.body}`);
    }
    
    // Progress indicator for large setup
    if (i % 1000 === 0) {
    console.log(`Created ${i} accounts...`);
    }
}

// Create 10 HOT ACCOUNTS that will get hammered simultaneously
const hotAccountTypes = [
    'Payroll Processor A', 'Payroll Processor B', 'Payment Gateway Main',
    'E-commerce Merchant', 'Corporate Treasury', 'Remittance Service',
    'Crypto Exchange', 'Mobile Payment Hub', 'B2B Settlement', 'Batch Processing'
];

for (let i = 0; i < 10; i++) {
    const hotAccountId = uuidv4();
    const hotResponse = http.post(`${BASE_URL}/rpc/create_account`, JSON.stringify({
    p_account_id: hotAccountId,
    p_account_code: `HOT-${i.toString().padStart(2, '0')}`,
    p_account_name: hotAccountTypes[i],
    p_account_type: 'ASSET',
    p_parent_account_id: null
    }), { headers: HEADERS });
    
    if (hotResponse.status === 200) {
    HOT_ACCOUNTS.push(hotAccountId);
    } else {
    console.log(`Failed to create hot account ${i}: ${hotResponse.status} - ${hotResponse.body}`);
    }
}

console.log(`✓ Created ${ACCOUNT_POOL.length} accounts (${POPULAR_ACCOUNTS.length} popular)`);
console.log(`✓ Created ${HOT_ACCOUNTS.length} hot accounts for multi-account locking test`);

return { 
    accounts: ACCOUNT_POOL, 
    popular: POPULAR_ACCOUNTS,
    hotAccounts: HOT_ACCOUNTS 
};
}

// Test 1: Pure Transaction Creation TPS
export function createTransactions(data) {
  const accounts = data.accounts;
  
  // Pick random debit/credit accounts
  const debitAccount = accounts[Math.floor(Math.random() * accounts.length)];
  const creditAccount = accounts[Math.floor(Math.random() * accounts.length)];
  
  if (debitAccount === creditAccount) return; // Skip same account
  
  const amount = Math.floor(Math.random() * 1000) + 10;
  
  const response = http.post(`${BASE_URL}/rpc/record_journal_entry`, JSON.stringify({
    p_entry_date: new Date().toISOString().split('T')[0],
    p_description: `TPS Test Transaction`,
    p_journal_lines: [
      {
        account_id: debitAccount,
        debit_amount: amount,
        credit_amount: 0,
        description: 'Debit'
      },
      {
        account_id: creditAccount,
        debit_amount: 0,
        credit_amount: amount,
        description: 'Credit'
      }
    ],
    p_reference_number: `TPS-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
    p_created_by: 'k6_tps_test'
  }), { headers: HEADERS });
  
  check(response, {
    'transaction_created': (r) => r.status === 200,
  });
}

// Test 2: Pure Balance Query TPS
export function queryBalances(data) {
  const accounts = data.accounts;
  const popular = data.popular;
  
  // 70% queries hit popular accounts (realistic distribution)
  const targetAccounts = Math.random() < 0.7 ? popular : accounts;
  const accountId = targetAccounts[Math.floor(Math.random() * targetAccounts.length)];
  
  const response = http.post(`${BASE_URL}/rpc/get_account_balance`, JSON.stringify({
    p_account_id: accountId
  }), { 
    headers: {
      ...HEADERS,
      'Accept': 'application/vnd.pgrst.object+json'
    }
  });
  
  check(response, {
    'balance_retrieved': (r) => r.status === 200,
    'balance_has_value': (r) => {
      try {
        const data = JSON.parse(r.body);
        return data.account_balance !== undefined;
      } catch (e) {
        return false;
      }
    }
  });
}

// Test 3: Single hot account hammer (for comparison)
export function hammerSingleHotAccount(data) {
  if (!data.hotAccounts || data.hotAccounts.length === 0) {
    console.error('Hot accounts not available for locking test');
    return;
  }
  
  const accounts = data.accounts;
  const hotAccount = data.hotAccounts[0]; // Use first hot account
  
  // Pick a random "other" account to complete the double-entry
  const otherAccount = accounts[Math.floor(Math.random() * accounts.length)];
  
  // Randomly choose if hot account is debit or credit side
  const hotIsDebit = Math.random() < 0.5;
  const amount = Math.floor(Math.random() * 1000) + 10;
  
  const lines = hotIsDebit ? [
    {
      account_id: hotAccount,
      debit_amount: amount,
      credit_amount: 0,
      description: 'Single hot account debit'
    },
    {
      account_id: otherAccount,
      debit_amount: 0,
      credit_amount: amount,
      description: 'Other account credit'
    }
  ] : [
    {
      account_id: otherAccount,
      debit_amount: amount,
      credit_amount: 0,
      description: 'Other account debit'
    },
    {
      account_id: hotAccount,
      debit_amount: 0,
      credit_amount: amount,
      description: 'Single hot account credit'
    }
  ];
  
  const response = http.post(`${BASE_URL}/rpc/record_journal_entry`, JSON.stringify({
    p_entry_date: new Date().toISOString().split('T')[0],
    p_description: `SINGLE HOT - Account Transaction`,
    p_journal_lines: lines,
    p_reference_number: `SINGLE-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
    p_created_by: 'k6_single_hot_test'
  }), { headers: HEADERS });
  
  check(response, {
    'single_hot_transaction_created': (r) => r.status === 200,
    'single_hot_no_timeout': (r) => r.timings.duration < 5000,
    'single_hot_reasonable_time': (r) => r.timings.duration < 2000,
  });
  
  if (response.timings.duration > 1000) {
    console.log(`SLOW single hot transaction: ${response.timings.duration}ms`);
  }
}

// Test 4: 🔥 MULTI-HOT ACCOUNT NIGHTMARE - The real banking killer
export function hammerMultipleHotAccounts(data) {
  if (!data.hotAccounts || data.hotAccounts.length === 0) {
    console.error('Hot accounts not available for multi-hot locking test');
    return;
  }
  
  const accounts = data.accounts;
  const hotAccounts = data.hotAccounts;
  
  // Pick a random hot account from the 10 available
  const hotAccount = hotAccounts[Math.floor(Math.random() * hotAccounts.length)];
  
  // 30% chance of hot-to-hot transfers (the worst case for locking)
  const isHotToHot = Math.random() < 0.3;
  const otherAccount = isHotToHot ? 
    hotAccounts[Math.floor(Math.random() * hotAccounts.length)] :
    accounts[Math.floor(Math.random() * accounts.length)];
  
  // Skip if same account selected
  if (hotAccount === otherAccount) return;
  
  const hotIsDebit = Math.random() < 0.5;
  const amount = Math.floor(Math.random() * 10000) + 100; // Larger amounts for payroll simulation
  
  const transactionType = isHotToHot ? 'HOT-TO-HOT' : 'HOT-TO-NORMAL';
  const description = isHotToHot ? 
    'Inter-processor settlement' : 
    'Batch payroll/payment processing';
  
  const lines = hotIsDebit ? [
    {
      account_id: hotAccount,
      debit_amount: amount,
      credit_amount: 0,
      description: `${transactionType} debit`
    },
    {
      account_id: otherAccount,
      debit_amount: 0,
      credit_amount: amount,
      description: `${transactionType} credit`
    }
  ] : [
    {
      account_id: otherAccount,
      debit_amount: amount,
      credit_amount: 0,
      description: `${transactionType} debit`
    },
    {
      account_id: hotAccount,
      debit_amount: 0,
      credit_amount: amount,
      description: `${transactionType} credit`
    }
  ];
  
  const response = http.post(`${BASE_URL}/rpc/record_journal_entry`, JSON.stringify({
    p_entry_date: new Date().toISOString().split('T')[0],
    p_description: description,
    p_journal_lines: lines,
    p_reference_number: `MULTI-${transactionType}-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
    p_created_by: 'k6_multi_hot_test'
  }), { headers: HEADERS });
  
  check(response, {
    'multi_hot_transaction_created': (r) => r.status === 200,
    'multi_hot_no_timeout': (r) => r.timings.duration < 8000, // More lenient for complex locking
    'multi_hot_acceptable_time': (r) => r.timings.duration < 3000,
  });
  
  // Log problematic transactions for analysis
  if (response.timings.duration > 2000) {
    console.log(`SLOW multi-hot ${transactionType}: ${response.timings.duration}ms (Status: ${response.status})`);
  }
  
  if (response.status !== 200) {
    console.log(`FAILED multi-hot ${transactionType}: ${response.status} - ${response.body.substring(0, 100)}`);
  }
}

// Test 5: Mixed Workload (80% queries, 20% transactions)
export function mixedWorkload(data) {
  if (Math.random() < 0.8) {
    // 80% balance queries
    queryBalances(data);
  } else {
    // 20% transaction creation
    createTransactions(data);
  }
}

// Summary function
export function teardown(data) {
  console.log('\n=== CORE BANKING LEDGER TPS DEMO RESULTS ===');
  console.log('Account Scale: 10,000 regular + 10 hot accounts');
  console.log('\nCheck the k6 output above for:');
  console.log('1. Transaction Creation TPS: "create_transactions" scenario');
  console.log('2. Balance Query TPS: "query_balances" scenario');
  console.log('3. Single Hot Account: "single_hot_account" scenario (25 TPS on 1 account)');
  console.log('4. 🔥 MULTI-HOT NIGHTMARE: "multi_hot_accounts" scenario');
  console.log('   - 100 TPS across 10 hot accounts (~10 TPS each)');
  console.log('   - 30% hot-to-hot transfers (worst case locking)');
  console.log('   - Tests: payroll processors, payment gateways, batch jobs');
  console.log('   - P95 should stay under 3s, P99 under 8s');
  console.log('5. Mixed Workload TPS: "mixed_workload" scenario');
  console.log('\nCRITICAL LOCKING THRESHOLDS:');
  console.log('- Single hot: <5% error rate, P95 <2s');
  console.log('- Multi hot: <10% error rate, P95 <3s (this is the killer test)');
  console.log('\nTotal test time: ~7 minutes');
  console.log('\nIf multi-hot test fails, your ledger has locking issues at scale.');
}
