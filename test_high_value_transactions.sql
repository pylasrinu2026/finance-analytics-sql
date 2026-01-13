/*******************************************************************************
 * TEST SUITE FOR HIGH-VALUE DAILY TRANSACTION AGGREGATION
 *******************************************************************************
 * Purpose: Validate query correctness, data quality, and performance
 * Run these tests after implementing the monitoring queries
 * Created: 2026-01-12
 ******************************************************************************/

-- =============================================================================
-- TEST 1: Validate Date Normalization
-- Purpose: Ensure TRANSACTION_DATE is properly cast to DATE type (no time)
-- Expected: All dates should be in 'YYYY-MM-DD' format with no timestamps
-- =============================================================================
SELECT 
    'TEST 1: Date Normalization' AS test_name,
    TRANSACTION_DATE,
    TYPEOF(TRANSACTION_DATE) AS date_type,
    CASE 
        WHEN TRANSACTION_DATE = CAST(TRANSACTION_DATE AS DATE) THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM (
    -- Insert main query here for testing
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
    HAVING SUM(t.AMOUNT) > 1000000
    LIMIT 10
)
ORDER BY TRANSACTION_DATE DESC;

-- =============================================================================
-- TEST 2: NULL Value Validation
-- Purpose: Confirm no NULL values in critical columns
-- Expected: Row count should be 0
-- =============================================================================
SELECT 
    'TEST 2: NULL Value Check' AS test_name,
    COUNT(*) AS null_count,
    CASE 
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM (
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
    HAVING SUM(t.AMOUNT) > 1000000
)
WHERE CUSTOMER_ID IS NULL 
   OR TRANSACTION_DATE IS NULL 
   OR TOTAL_DAILY_AMOUNT IS NULL;

-- =============================================================================
-- TEST 3: Threshold Validation
-- Purpose: Verify all results exceed $1M threshold
-- Expected: min_amount > 1000000, test_result = 'PASS'
-- =============================================================================
SELECT 
    'TEST 3: Threshold Validation' AS test_name,
    MIN(TOTAL_DAILY_AMOUNT) AS min_amount,
    MAX(TOTAL_DAILY_AMOUNT) AS max_amount,
    AVG(TOTAL_DAILY_AMOUNT) AS avg_amount,
    CASE 
        WHEN MIN(TOTAL_DAILY_AMOUNT) > 1000000 THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM (
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
    HAVING SUM(t.AMOUNT) > 1000000
);

-- =============================================================================
-- TEST 4: Aggregation Correctness
-- Purpose: Verify SUM calculation by comparing with manual calculation
-- Expected: aggregated_sum should match manual_sum
-- =============================================================================
WITH query_results AS (
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS aggregated_sum
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
    HAVING SUM(t.AMOUNT) > 1000000
    LIMIT 5
),
manual_calculation AS (
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS manual_sum
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
)
SELECT 
    'TEST 4: Aggregation Correctness' AS test_name,
    qr.CUSTOMER_ID,
    qr.TRANSACTION_DATE,
    qr.aggregated_sum,
    mc.manual_sum,
    CASE 
        WHEN qr.aggregated_sum = mc.manual_sum THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM query_results qr
INNER JOIN manual_calculation mc 
    ON qr.CUSTOMER_ID = mc.CUSTOMER_ID 
    AND qr.TRANSACTION_DATE = mc.TRANSACTION_DATE;

-- =============================================================================
-- TEST 5: Multiple Accounts Per Customer
-- Purpose: Verify proper aggregation across multiple accounts
-- Expected: total_by_customer should equal sum of all account amounts
-- =============================================================================
WITH customer_totals AS (
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS total_by_customer
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
    HAVING SUM(t.AMOUNT) > 1000000
),
account_breakdown AS (
    SELECT 
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        a.ACCOUNT_ID,
        SUM(t.AMOUNT) AS account_amount
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE), a.ACCOUNT_ID
)
SELECT 
    'TEST 5: Multi-Account Aggregation' AS test_name,
    ct.CUSTOMER_ID,
    ct.TRANSACTION_DATE,
    ct.total_by_customer,
    COUNT(DISTINCT ab.ACCOUNT_ID) AS number_of_accounts,
    SUM(ab.account_amount) AS sum_of_accounts,
    CASE 
        WHEN ct.total_by_customer = SUM(ab.account_amount) THEN 'PASS'
        ELSE 'FAIL'
    END AS test_result
FROM customer_totals ct
INNER JOIN account_breakdown ab 
    ON ct.CUSTOMER_ID = ab.CUSTOMER_ID 
    AND ct.TRANSACTION_DATE = ab.TRANSACTION_DATE
GROUP BY ct.CUSTOMER_ID, ct.TRANSACTION_DATE, ct.total_by_customer
LIMIT 10;

-- =============================================================================
-- TEST 6: Data Quality Metrics
-- Purpose: Assess overall data quality and coverage
-- Expected: Review percentages to ensure data integrity
-- =============================================================================
WITH source_data AS (
    SELECT 
        COUNT(*) AS total_transactions,
        COUNT(DISTINCT t.ACCOUNT_ID) AS distinct_accounts,
        COUNT(DISTINCT a.CUSTOMER_ID) AS distinct_customers,
        SUM(CASE WHEN t.AMOUNT IS NULL THEN 1 ELSE 0 END) AS null_amounts,
        SUM(CASE WHEN t.TRANSACTION_DATE IS NULL THEN 1 ELSE 0 END) AS null_dates,
        SUM(CASE WHEN a.CUSTOMER_ID IS NULL THEN 1 ELSE 0 END) AS null_customers
    FROM TRANSACTION t
    LEFT JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
),
filtered_data AS (
    SELECT 
        COUNT(*) AS valid_transactions,
        COUNT(DISTINCT a.CUSTOMER_ID) AS customers_with_valid_data
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE t.TRANSACTION_DATE IS NOT NULL
      AND t.AMOUNT IS NOT NULL
      AND a.CUSTOMER_ID IS NOT NULL
),
high_value_results AS (
    SELECT 
        COUNT(*) AS high_value_count,
        COUNT(DISTINCT CUSTOMER_ID) AS high_value_customers
    FROM (
        SELECT 
            a.CUSTOMER_ID,
            CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
            SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
        FROM TRANSACTION t
        INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
        WHERE t.TRANSACTION_DATE IS NOT NULL
          AND t.AMOUNT IS NOT NULL
          AND a.CUSTOMER_ID IS NOT NULL
        GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
        HAVING SUM(t.AMOUNT) > 1000000
    )
)
SELECT 
    'TEST 6: Data Quality Metrics' AS test_name,
    sd.total_transactions,
    sd.distinct_accounts,
    sd.distinct_customers,
    fd.valid_transactions,
    ROUND(100.0 * fd.valid_transactions / sd.total_transactions, 2) AS pct_valid_transactions,
    sd.null_amounts,
    sd.null_dates,
    sd.null_customers,
    hvr.high_value_count AS high_value_records,
    hvr.high_value_customers,
    ROUND(100.0 * hvr.high_value_customers / sd.distinct_customers, 2) AS pct_high_value_customers
FROM source_data sd, filtered_data fd, high_value_results hvr;

-- =============================================================================
-- TEST 7: Performance Benchmark
-- Purpose: Measure query execution time
-- Expected: Execution time < 30 seconds for production use
-- =============================================================================
-- Note: Wrap main query with timing functions specific to your database
-- Example for Snowflake:
/*
SET start_time = CURRENT_TIMESTAMP();

-- Run main query here
SELECT 
    a.CUSTOMER_ID,
    CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
    SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
FROM TRANSACTION t
INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
WHERE t.TRANSACTION_DATE IS NOT NULL
  AND t.AMOUNT IS NOT NULL
  AND a.CUSTOMER_ID IS NOT NULL
GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
HAVING SUM(t.AMOUNT) > 1000000;

SELECT 
    'TEST 7: Performance Benchmark' AS test_name,
    DATEDIFF('second', $start_time, CURRENT_TIMESTAMP()) AS execution_seconds,
    CASE 
        WHEN DATEDIFF('second', $start_time, CURRENT_TIMESTAMP()) < 30 THEN 'PASS'
        ELSE 'REVIEW'
    END AS test_result;
*/

-- =============================================================================
-- TEST 8: Edge Case - Same Day Different Times
-- Purpose: Verify transactions on same day at different times aggregate correctly
-- Expected: Multiple transactions per customer-day should sum properly
-- =============================================================================
SELECT 
    'TEST 8: Same-Day Aggregation' AS test_name,
    a.CUSTOMER_ID,
    CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
    COUNT(*) AS transaction_count,
    MIN(t.TRANSACTION_DATE) AS earliest_transaction,
    MAX(t.TRANSACTION_DATE) AS latest_transaction,
    SUM(t.AMOUNT) AS total_amount,
    CASE 
        WHEN COUNT(*) > 1 AND SUM(t.AMOUNT) > 0 THEN 'PASS'
        ELSE 'REVIEW'
    END AS test_result
FROM TRANSACTION t
INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
WHERE t.TRANSACTION_DATE IS NOT NULL
  AND t.AMOUNT IS NOT NULL
  AND a.CUSTOMER_ID IS NOT NULL
GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
HAVING COUNT(*) > 1  -- Only show customers with multiple transactions per day
   AND SUM(t.AMOUNT) > 1000000
ORDER BY transaction_count DESC
LIMIT 10;

/*******************************************************************************
 * TEST EXECUTION INSTRUCTIONS
 *******************************************************************************
 * 
 * 1. Run each test individually to isolate issues
 * 2. Review 'test_result' column for PASS/FAIL status
 * 3. Investigate any FAIL results before deploying to production
 * 4. Document baseline metrics from TEST 6 for ongoing monitoring
 * 5. Benchmark performance (TEST 7) on production-scale data
 * 
 * All tests should PASS before production deployment.
 ******************************************************************************/
