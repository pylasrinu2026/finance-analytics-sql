/*******************************************************************************
 * HIGH-VALUE TRANSACTION REPORT - COMPREHENSIVE TEST SUITE
 *******************************************************************************
 * Purpose: Validate functionality of high-value transaction reporting objects
 * 
 * Test Coverage:
 *   - View functionality and column output
 *   - Stored procedure with various date ranges
 *   - Edge cases and error handling
 *   - Performance benchmarking
 *   - Security and permissions validation
 * 
 * Created: 2026-01-12
 * Prerequisites: All objects deployed (view, procedure, permissions)
 *******************************************************************************
 *
 * EXECUTION INSTRUCTIONS:
 * -----------------------
 * Run each test section sequentially and verify expected results.
 * Some tests may return no data if thresholds are not met (this is normal).
 * Document any failures and review troubleshooting guide.
 *
 ******************************************************************************/

/*******************************************************************************
 * TEST 1: VIEW BASIC FUNCTIONALITY
 * Expected: Query executes successfully, returns columns as defined
 ******************************************************************************/
SELECT '=== TEST 1: VIEW BASIC FUNCTIONALITY ===' AS test_name;

-- Test 1.1: Select all columns (limit to 5 rows for inspection)
SELECT 
    PRIORITY_RANK,
    CUSTOMER_ID,
    CUSTOMER_NAME,
    CUSTOMER_RISK_LEVEL,
    COUNTRY,
    ACCOUNT_COUNT,
    PRIMARY_ACCOUNT_NUMBER,
    TRANSACTION_DATE,
    TRANSACTION_COUNT,
    TOTAL_DAILY_AMOUNT,
    AVG_TRANSACTION_AMOUNT,
    MAX_SINGLE_TRANSACTION,
    DAYS_SINCE_LAST_HIGH_VALUE,
    REPORT_GENERATED_TIMESTAMP
FROM vw_high_value_transactions_report
LIMIT 5;

-- Test 1.2: Verify row count
SELECT 
    'Total high-value transaction records' AS metric,
    COUNT(*) AS value
FROM vw_high_value_transactions_report;

-- Test 1.3: Verify ranking is working (priority_rank should be sequential)
SELECT 
    'Ranking validation' AS test,
    MIN(PRIORITY_RANK) AS min_rank,
    MAX(PRIORITY_RANK) AS max_rank,
    COUNT(DISTINCT PRIORITY_RANK) AS unique_ranks
FROM vw_high_value_transactions_report;

-- Test 1.4: Verify threshold enforcement (all amounts should be > 1M)
SELECT 
    'Threshold validation' AS test,
    MIN(TOTAL_DAILY_AMOUNT) AS min_amount,
    MAX(TOTAL_DAILY_AMOUNT) AS max_amount,
    CASE 
        WHEN MIN(TOTAL_DAILY_AMOUNT) > 1000000 THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Found amount below $1M threshold'
    END AS result
FROM vw_high_value_transactions_report;

/*******************************************************************************
 * TEST 2: DATA QUALITY VALIDATION
 * Expected: No NULL values in critical columns
 ******************************************************************************/
SELECT '=== TEST 2: DATA QUALITY VALIDATION ===' AS test_name;

-- Test 2.1: Check for NULL values in key columns
SELECT 
    'NULL value check' AS test,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN CUSTOMER_ID IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN CUSTOMER_NAME IS NULL THEN 1 ELSE 0 END) AS null_customer_name,
    SUM(CASE WHEN TRANSACTION_DATE IS NULL THEN 1 ELSE 0 END) AS null_transaction_date,
    SUM(CASE WHEN TOTAL_DAILY_AMOUNT IS NULL THEN 1 ELSE 0 END) AS null_total_amount,
    CASE 
        WHEN SUM(CASE WHEN CUSTOMER_ID IS NULL THEN 1 ELSE 0 END) = 0 
         AND SUM(CASE WHEN TRANSACTION_DATE IS NULL THEN 1 ELSE 0 END) = 0
         AND SUM(CASE WHEN TOTAL_DAILY_AMOUNT IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Found NULL values'
    END AS result
FROM vw_high_value_transactions_report;

-- Test 2.2: Verify transaction count matches aggregation
-- (Each row should have at least 1 transaction)
SELECT 
    'Transaction count validation' AS test,
    MIN(TRANSACTION_COUNT) AS min_count,
    AVG(TRANSACTION_COUNT) AS avg_count,
    MAX(TRANSACTION_COUNT) AS max_count,
    CASE 
        WHEN MIN(TRANSACTION_COUNT) >= 1 THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Found zero transaction count'
    END AS result
FROM vw_high_value_transactions_report;

/*******************************************************************************
 * TEST 3: BUSINESS LOGIC VALIDATION
 * Expected: Aggregation logic matches original query
 ******************************************************************************/
SELECT '=== TEST 3: BUSINESS LOGIC VALIDATION ===' AS test_name;

-- Test 3.1: Compare view results with base aggregation query
-- (Should match the original high_value_daily_transactions.sql logic)
WITH base_aggregation AS (
    SELECT
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE 
        t.TRANSACTION_DATE IS NOT NULL
        AND t.AMOUNT IS NOT NULL
        AND a.CUSTOMER_ID IS NOT NULL
    GROUP BY a.CUSTOMER_ID, CAST(t.TRANSACTION_DATE AS DATE)
    HAVING SUM(t.AMOUNT) > 1000000
)
SELECT 
    'Aggregation logic validation' AS test,
    (SELECT COUNT(*) FROM base_aggregation) AS base_query_count,
    (SELECT COUNT(*) FROM vw_high_value_transactions_report) AS view_count,
    CASE 
        WHEN (SELECT COUNT(*) FROM base_aggregation) = 
             (SELECT COUNT(*) FROM vw_high_value_transactions_report)
        THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Row count mismatch'
    END AS result;

-- Test 3.2: Verify customer enrichment (all customers should have names)
SELECT 
    'Customer enrichment validation' AS test,
    COUNT(*) AS total_customers,
    COUNT(DISTINCT CUSTOMER_ID) AS unique_customers,
    SUM(CASE WHEN CUSTOMER_NAME IS NOT NULL THEN 1 ELSE 0 END) AS with_name,
    CASE 
        WHEN COUNT(*) = SUM(CASE WHEN CUSTOMER_NAME IS NOT NULL THEN 1 ELSE 0 END)
        THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Some customers missing names'
    END AS result
FROM vw_high_value_transactions_report;

/*******************************************************************************
 * TEST 4: TEMPORAL ANALYSIS VALIDATION
 * Expected: Days_since_last_high_value calculated correctly
 ******************************************************************************/
SELECT '=== TEST 4: TEMPORAL ANALYSIS VALIDATION ===' AS test_name;

-- Test 4.1: Verify days_since_last_high_value logic
SELECT 
    CUSTOMER_ID,
    CUSTOMER_NAME,
    TRANSACTION_DATE,
    DAYS_SINCE_LAST_HIGH_VALUE,
    LAG(TRANSACTION_DATE) OVER (
        PARTITION BY CUSTOMER_ID 
        ORDER BY TRANSACTION_DATE
    ) AS previous_date,
    DATEDIFF(
        day,
        LAG(TRANSACTION_DATE) OVER (PARTITION BY CUSTOMER_ID ORDER BY TRANSACTION_DATE),
        TRANSACTION_DATE
    ) AS calculated_days
FROM vw_high_value_transactions_report
WHERE DAYS_SINCE_LAST_HIGH_VALUE IS NOT NULL
LIMIT 10;

-- Test 4.2: Check for first occurrence (should have NULL days_since_last_high_value)
SELECT 
    'First occurrence validation' AS test,
    COUNT(CASE WHEN DAYS_SINCE_LAST_HIGH_VALUE IS NULL THEN 1 END) AS first_occurrences,
    COUNT(*) AS total_records,
    CASE 
        WHEN COUNT(CASE WHEN DAYS_SINCE_LAST_HIGH_VALUE IS NULL THEN 1 END) > 0
        THEN 'PASS ✓'
        ELSE 'WARNING - No first occurrences found'
    END AS result
FROM vw_high_value_transactions_report;

/*******************************************************************************
 * TEST 5: STORED PROCEDURE FUNCTIONALITY
 * Expected: Procedure executes with various date ranges
 ******************************************************************************/
SELECT '=== TEST 5: STORED PROCEDURE FUNCTIONALITY ===' AS test_name;

-- Test 5.1: Execute procedure with 30-day range
CALL sp_generate_high_value_report(
    CURRENT_DATE - 30,
    CURRENT_DATE
);

-- Test 5.2: Execute procedure with 7-day range
CALL sp_generate_high_value_report(
    CURRENT_DATE - 7,
    CURRENT_DATE
);

-- Test 5.3: Execute procedure with single-day range
CALL sp_generate_high_value_report(
    CURRENT_DATE - 1,
    CURRENT_DATE - 1
);

-- Test 5.4: Execute procedure with custom date range
CALL sp_generate_high_value_report(
    '2026-01-01'::DATE,
    '2026-01-31'::DATE
);

/*******************************************************************************
 * TEST 6: ERROR HANDLING VALIDATION
 * Expected: Procedure returns appropriate error messages
 ******************************************************************************/
SELECT '=== TEST 6: ERROR HANDLING VALIDATION ===' AS test_name;

-- Test 6.1: NULL start_date (should return error)
-- Uncomment to test (will produce error):
-- CALL sp_generate_high_value_report(NULL, CURRENT_DATE);

-- Test 6.2: NULL end_date (should return error)
-- Uncomment to test (will produce error):
-- CALL sp_generate_high_value_report(CURRENT_DATE - 30, NULL);

-- Test 6.3: Invalid date range (start > end, should return error)
-- Uncomment to test (will produce error):
-- CALL sp_generate_high_value_report(CURRENT_DATE, CURRENT_DATE - 30);

-- Test 6.4: Large date range (should return warning but execute)
-- Uncomment to test (may be slow):
-- CALL sp_generate_high_value_report(CURRENT_DATE - 400, CURRENT_DATE);

/*******************************************************************************
 * TEST 7: PERFORMANCE BENCHMARKING
 * Expected: Query executes within acceptable time limits (<5 seconds)
 ******************************************************************************/
SELECT '=== TEST 7: PERFORMANCE BENCHMARKING ===' AS test_name;

-- Test 7.1: Measure view query performance
-- Run with EXPLAIN ANALYZE to see execution plan and timing
EXPLAIN ANALYZE
SELECT * 
FROM vw_high_value_transactions_report
WHERE TRANSACTION_DATE >= CURRENT_DATE - 30
LIMIT 100;

-- Test 7.2: Measure procedure performance
-- Check query history for execution time after running:
CALL sp_generate_high_value_report(
    CURRENT_DATE - 30,
    CURRENT_DATE
);

-- Test 7.3: Query execution history (Snowflake specific)
-- Uncomment for Snowflake environments:
-- SELECT
--     QUERY_TEXT,
--     TOTAL_ELAPSED_TIME / 1000 AS execution_seconds,
--     BYTES_SCANNED,
--     ROWS_PRODUCED
-- FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
-- WHERE QUERY_TEXT ILIKE '%high_value_transactions_report%'
--     AND START_TIME >= CURRENT_TIMESTAMP - INTERVAL '1 hour'
-- ORDER BY START_TIME DESC
-- LIMIT 10;

/*******************************************************************************
 * TEST 8: FILTERING AND SORTING VALIDATION
 * Expected: Filters and sorts work correctly on view
 ******************************************************************************/
SELECT '=== TEST 8: FILTERING AND SORTING VALIDATION ===' AS test_name;

-- Test 8.1: Filter by date range
SELECT 
    'Date range filter test' AS test,
    COUNT(*) AS matching_records
FROM vw_high_value_transactions_report
WHERE TRANSACTION_DATE BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE;

-- Test 8.2: Filter by customer risk level
SELECT 
    'Risk level filter test' AS test,
    CUSTOMER_RISK_LEVEL,
    COUNT(*) AS customer_count
FROM vw_high_value_transactions_report
GROUP BY CUSTOMER_RISK_LEVEL
ORDER BY customer_count DESC;

-- Test 8.3: Filter by amount threshold
SELECT 
    'Amount threshold filter test' AS test,
    COUNT(*) AS above_2m_count
FROM vw_high_value_transactions_report
WHERE TOTAL_DAILY_AMOUNT > 2000000;

-- Test 8.4: Verify sorting by priority rank
SELECT 
    'Priority sort validation' AS test,
    PRIORITY_RANK,
    TOTAL_DAILY_AMOUNT
FROM vw_high_value_transactions_report
ORDER BY PRIORITY_RANK
LIMIT 10;

/*******************************************************************************
 * TEST 9: AGGREGATION AND REPORTING SCENARIOS
 * Expected: Common reporting queries execute correctly
 ******************************************************************************/
SELECT '=== TEST 9: AGGREGATION AND REPORTING SCENARIOS ===' AS test_name;

-- Test 9.1: Top 10 high-value customers (by total amount)
SELECT 
    CUSTOMER_ID,
    CUSTOMER_NAME,
    COUNT(*) AS high_value_days,
    SUM(TOTAL_DAILY_AMOUNT) AS total_amount,
    AVG(TOTAL_DAILY_AMOUNT) AS avg_daily_amount
FROM vw_high_value_transactions_report
WHERE TRANSACTION_DATE >= CURRENT_DATE - 90
GROUP BY CUSTOMER_ID, CUSTOMER_NAME
ORDER BY total_amount DESC
LIMIT 10;

-- Test 9.2: Daily trend analysis
SELECT 
    TRANSACTION_DATE,
    COUNT(DISTINCT CUSTOMER_ID) AS unique_customers,
    COUNT(*) AS high_value_events,
    SUM(TOTAL_DAILY_AMOUNT) AS total_amount,
    AVG(TOTAL_DAILY_AMOUNT) AS avg_amount
FROM vw_high_value_transactions_report
WHERE TRANSACTION_DATE >= CURRENT_DATE - 30
GROUP BY TRANSACTION_DATE
ORDER BY TRANSACTION_DATE DESC;

-- Test 9.3: Customer frequency analysis
SELECT 
    CASE 
        WHEN high_value_days >= 20 THEN '20+ days'
        WHEN high_value_days >= 10 THEN '10-19 days'
        WHEN high_value_days >= 5 THEN '5-9 days'
        ELSE '1-4 days'
    END AS frequency_bucket,
    COUNT(DISTINCT CUSTOMER_ID) AS customer_count
FROM (
    SELECT 
        CUSTOMER_ID,
        COUNT(*) AS high_value_days
    FROM vw_high_value_transactions_report
    WHERE TRANSACTION_DATE >= CURRENT_DATE - 90
    GROUP BY CUSTOMER_ID
) AS customer_frequency
GROUP BY 
    CASE 
        WHEN high_value_days >= 20 THEN '20+ days'
        WHEN high_value_days >= 10 THEN '10-19 days'
        WHEN high_value_days >= 5 THEN '5-9 days'
        ELSE '1-4 days'
    END
ORDER BY MIN(high_value_days) DESC;

-- Test 9.4: Country distribution
SELECT 
    COUNTRY,
    COUNT(DISTINCT CUSTOMER_ID) AS unique_customers,
    COUNT(*) AS high_value_events,
    SUM(TOTAL_DAILY_AMOUNT) AS total_amount
FROM vw_high_value_transactions_report
WHERE TRANSACTION_DATE >= CURRENT_DATE - 90
GROUP BY COUNTRY
ORDER BY total_amount DESC;

/*******************************************************************************
 * TEST 10: PERMISSIONS VALIDATION
 * Expected: Appropriate access based on role
 ******************************************************************************/
SELECT '=== TEST 10: PERMISSIONS VALIDATION ===' AS test_name;

-- Test 10.1: View permissions check
-- Uncomment and run as different roles:
-- SHOW GRANTS ON VIEW vw_high_value_transactions_report;

-- Test 10.2: Procedure permissions check
-- SHOW GRANTS ON PROCEDURE sp_generate_high_value_report(DATE, DATE);

-- Test 10.3: Test access as compliance_analyst_role
-- USE ROLE compliance_analyst_role;
-- SELECT COUNT(*) FROM vw_high_value_transactions_report;
-- CALL sp_generate_high_value_report(CURRENT_DATE - 7, CURRENT_DATE);

-- Test 10.4: Test access as executive_reporting_role
-- USE ROLE executive_reporting_role;
-- SELECT COUNT(*) FROM vw_high_value_transactions_report;
-- Should FAIL: CALL sp_generate_high_value_report(CURRENT_DATE - 7, CURRENT_DATE);

/*******************************************************************************
 * TEST 11: EDGE CASES
 * Expected: Graceful handling of unusual scenarios
 ******************************************************************************/
SELECT '=== TEST 11: EDGE CASES ===' AS test_name;

-- Test 11.1: Customer with multiple accounts
SELECT 
    'Multiple accounts test' AS test,
    CUSTOMER_ID,
    CUSTOMER_NAME,
    ACCOUNT_COUNT,
    TOTAL_DAILY_AMOUNT
FROM vw_high_value_transactions_report
WHERE ACCOUNT_COUNT > 1
LIMIT 5;

-- Test 11.2: Same-day multiple high-value events (should aggregate)
SELECT 
    'Same-day aggregation test' AS test,
    CUSTOMER_ID,
    TRANSACTION_DATE,
    TRANSACTION_COUNT,
    TOTAL_DAILY_AMOUNT
FROM vw_high_value_transactions_report
WHERE TRANSACTION_COUNT >= 10
ORDER BY TRANSACTION_COUNT DESC
LIMIT 5;

-- Test 11.3: Customers with consecutive high-value days
SELECT 
    'Consecutive days test' AS test,
    CUSTOMER_ID,
    CUSTOMER_NAME,
    TRANSACTION_DATE,
    DAYS_SINCE_LAST_HIGH_VALUE
FROM vw_high_value_transactions_report
WHERE DAYS_SINCE_LAST_HIGH_VALUE = 1
ORDER BY TRANSACTION_DATE DESC
LIMIT 10;

-- Test 11.4: Very high transaction amounts (outliers)
SELECT 
    'Outlier detection test' AS test,
    CUSTOMER_ID,
    CUSTOMER_NAME,
    TRANSACTION_DATE,
    TOTAL_DAILY_AMOUNT,
    TRANSACTION_COUNT
FROM vw_high_value_transactions_report
WHERE TOTAL_DAILY_AMOUNT > 10000000  -- $10M threshold
ORDER BY TOTAL_DAILY_AMOUNT DESC
LIMIT 10;

/*******************************************************************************
 * TEST 12: DATA INTEGRITY CHECKS
 * Expected: All data relationships maintained
 ******************************************************************************/
SELECT '=== TEST 12: DATA INTEGRITY CHECKS ===' AS test_name;

-- Test 12.1: Verify all customers exist in CUSTOMER table
SELECT 
    'Customer integrity check' AS test,
    COUNT(DISTINCT v.CUSTOMER_ID) AS view_customers,
    COUNT(DISTINCT c.CUSTOMER_ID) AS matching_customers,
    CASE 
        WHEN COUNT(DISTINCT v.CUSTOMER_ID) = COUNT(DISTINCT c.CUSTOMER_ID)
        THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Orphaned customers in view'
    END AS result
FROM vw_high_value_transactions_report v
LEFT JOIN CUSTOMER c ON v.CUSTOMER_ID = c.CUSTOMER_ID;

-- Test 12.2: Verify accounts exist in ACCOUNT table
SELECT 
    'Account integrity check' AS test,
    COUNT(DISTINCT v.PRIMARY_ACCOUNT_NUMBER) AS view_accounts,
    COUNT(DISTINCT a.ACCOUNT_ID) AS matching_accounts,
    CASE 
        WHEN COUNT(DISTINCT v.PRIMARY_ACCOUNT_NUMBER) = COUNT(DISTINCT a.ACCOUNT_ID)
        THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Orphaned accounts in view'
    END AS result
FROM vw_high_value_transactions_report v
LEFT JOIN ACCOUNT a ON v.PRIMARY_ACCOUNT_NUMBER = a.ACCOUNT_ID;

-- Test 12.3: Cross-validate transaction amounts
SELECT 
    'Amount validation' AS test,
    v.CUSTOMER_ID,
    v.TRANSACTION_DATE,
    v.TOTAL_DAILY_AMOUNT AS view_amount,
    SUM(t.AMOUNT) AS calculated_amount,
    CASE 
        WHEN ABS(v.TOTAL_DAILY_AMOUNT - SUM(t.AMOUNT)) < 0.01
        THEN 'PASS ✓'
        ELSE 'FAIL ✗ - Amount mismatch'
    END AS result
FROM vw_high_value_transactions_report v
INNER JOIN ACCOUNT a ON v.PRIMARY_ACCOUNT_NUMBER = a.ACCOUNT_ID
INNER JOIN TRANSACTION t ON a.ACCOUNT_ID = t.ACCOUNT_ID 
    AND CAST(t.TRANSACTION_DATE AS DATE) = v.TRANSACTION_DATE
GROUP BY v.CUSTOMER_ID, v.TRANSACTION_DATE, v.TOTAL_DAILY_AMOUNT
LIMIT 10;

/*******************************************************************************
 * TEST SUMMARY
 * Generate overall test results summary
 ******************************************************************************/
SELECT '=== TEST SUMMARY ===' AS test_name;

SELECT 
    'Total test cases executed' AS metric,
    '12 test categories' AS value
UNION ALL
SELECT 
    'Critical tests',
    'Business logic, data quality, permissions'
UNION ALL
SELECT 
    'Performance tests',
    'Query timing, indexing validation'
UNION ALL
SELECT 
    'Next steps',
    'Review any FAIL results and consult troubleshooting guide';

/*******************************************************************************
 * END OF TEST SUITE
 * 
 * EXPECTED OUTCOMES:
 * ------------------
 * - All "PASS ✓" results indicate successful validation
 * - "FAIL ✗" results require investigation and remediation
 * - "WARNING" results may be acceptable depending on data volume
 * - Some tests may return 0 rows if no data meets criteria (this is normal)
 * 
 * TROUBLESHOOTING:
 * ----------------
 * - If many tests fail, verify base tables (TRANSACTION, ACCOUNT, CUSTOMER) exist
 * - If performance is slow, ensure indexes are created as recommended
 * - If permissions tests fail, verify roles are configured correctly
 * - Consult HIGH_VALUE_REPORT_IMPLEMENTATION_GUIDE.md for detailed troubleshooting
 * 
 ******************************************************************************/
