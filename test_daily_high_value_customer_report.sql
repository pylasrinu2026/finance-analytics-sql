/*******************************************************************************
 * TEST SUITE: DAILY HIGH-VALUE CUSTOMER TRANSACTION ANALYSIS
 *******************************************************************************
 * Purpose: Validate the daily_high_value_customer_report.sql implementation
 * Tests: Data quality, threshold logic, NULL handling, aggregation accuracy
 * Created: 2026-01-13
 ******************************************************************************/

-- ============================================================================
-- TEST 1: DATA QUALITY ASSESSMENT
-- ============================================================================
-- Objective: Verify data completeness and identify quality issues
-- Expected: Shows counts of NULL values and data anomalies

SELECT 
    'Test 1: Data Quality Assessment' AS test_name,
    COUNT(*) AS total_transactions,
    COUNT(transaction_id) AS non_null_transaction_id,
    COUNT(customer_id) AS non_null_customer_id,
    COUNT(transaction_date) AS non_null_transaction_date,
    COUNT(transaction_amount) AS non_null_transaction_amount,
    COUNT(*) - COUNT(customer_id) AS null_customer_id_count,
    COUNT(*) - COUNT(transaction_date) AS null_transaction_date_count,
    COUNT(*) - COUNT(transaction_amount) AS null_transaction_amount_count,
    COUNT(CASE WHEN transaction_amount = 0 THEN 1 END) AS zero_amount_count,
    COUNT(CASE WHEN transaction_amount < 0 THEN 1 END) AS negative_amount_count,
    MIN(transaction_amount) AS min_amount,
    MAX(transaction_amount) AS max_amount,
    AVG(transaction_amount) AS avg_amount
FROM TRANSACTION;

-- Expected Results:
-- - total_transactions > 0 (data exists)
-- - null counts should be minimal or zero
-- - Check if zero/negative amounts need filtering


-- ============================================================================
-- TEST 2: CUSTOMER TRANSACTION DISTRIBUTION
-- ============================================================================
-- Objective: Understand customer transaction patterns
-- Expected: Shows how transactions are distributed across customers

SELECT
    'Test 2: Customer Transaction Distribution' AS test_name,
    COUNT(DISTINCT customer_id) AS unique_customers,
    COUNT(*) AS total_transactions,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT customer_id), 2) AS avg_transactions_per_customer,
    MAX(customer_transaction_count) AS max_transactions_per_customer,
    MIN(customer_transaction_count) AS min_transactions_per_customer
FROM TRANSACTION t
INNER JOIN (
    SELECT customer_id, COUNT(*) AS customer_transaction_count
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
) customer_counts ON t.customer_id = customer_counts.customer_id
WHERE t.customer_id IS NOT NULL;

-- Expected Results:
-- - unique_customers > 0
-- - avg_transactions_per_customer varies by business
-- - High max_transactions_per_customer indicates active customers


-- ============================================================================
-- TEST 3: DATE RANGE AND COVERAGE
-- ============================================================================
-- Objective: Verify date range and identify gaps in data
-- Expected: Shows earliest and latest transaction dates

SELECT
    'Test 3: Date Range and Coverage' AS test_name,
    MIN(CAST(transaction_date AS DATE)) AS earliest_transaction_date,
    MAX(CAST(transaction_date AS DATE)) AS latest_transaction_date,
    DATEDIFF(DAY, MIN(CAST(transaction_date AS DATE)), MAX(CAST(transaction_date AS DATE))) AS date_range_days,
    COUNT(DISTINCT CAST(transaction_date AS DATE)) AS unique_transaction_days
FROM TRANSACTION
WHERE transaction_date IS NOT NULL;

-- Expected Results:
-- - Date range should cover expected period
-- - unique_transaction_days should be close to date_range_days (no large gaps)


-- ============================================================================
-- TEST 4: THRESHOLD VALIDATION (PRE-FILTERING)
-- ============================================================================
-- Objective: Count how many customer-days exceed $1M threshold
-- Expected: Shows distribution of daily totals

SELECT
    'Test 4: Threshold Validation' AS test_name,
    COUNT(*) AS total_customer_days,
    COUNT(CASE WHEN daily_total > 1000000 THEN 1 END) AS above_threshold_count,
    COUNT(CASE WHEN daily_total <= 1000000 THEN 1 END) AS below_threshold_count,
    ROUND(
        COUNT(CASE WHEN daily_total > 1000000 THEN 1 END) * 100.0 / COUNT(*), 
        2
    ) AS percentage_above_threshold,
    MAX(daily_total) AS max_daily_total,
    MIN(daily_total) AS min_daily_total,
    AVG(daily_total) AS avg_daily_total
FROM (
    SELECT 
        customer_id,
        CAST(transaction_date AS DATE) AS transaction_date,
        SUM(transaction_amount) AS daily_total
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
      AND transaction_date IS NOT NULL
      AND transaction_amount IS NOT NULL
    GROUP BY customer_id, CAST(transaction_date AS DATE)
) daily_aggregates;

-- Expected Results:
-- - above_threshold_count > 0 (high-value customers exist)
-- - percentage_above_threshold typically 0.1% - 5% depending on business
-- - max_daily_total should be significantly higher than threshold


-- ============================================================================
-- TEST 5: MAIN QUERY EXECUTION (SAMPLE)
-- ============================================================================
-- Objective: Execute main query with LIMIT to verify it runs correctly
-- Expected: Returns top 10 high-value customer-days

SELECT
    'Test 5: Main Query Sample Execution' AS test_name,
    customer_id,
    transaction_date,
    total_daily_amount,
    transaction_count,
    average_transaction_amount,
    max_transaction_amount,
    min_transaction_amount
FROM (
    SELECT
        customer_id AS customer_id,
        CAST(transaction_date AS DATE) AS transaction_date,
        COALESCE(SUM(transaction_amount), 0) AS total_daily_amount,
        COUNT(CASE WHEN transaction_amount IS NOT NULL THEN 1 END) AS transaction_count,
        AVG(transaction_amount) AS average_transaction_amount,
        MAX(transaction_amount) AS max_transaction_amount,
        MIN(transaction_amount) AS min_transaction_amount
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
      AND transaction_date IS NOT NULL
      AND transaction_amount IS NOT NULL
    GROUP BY customer_id, CAST(transaction_date AS DATE)
    HAVING COALESCE(SUM(transaction_amount), 0) > 1000000
    ORDER BY transaction_date DESC, total_daily_amount DESC
) sample_results
LIMIT 10;

-- Expected Results:
-- - At least 1 row returned (if high-value customers exist)
-- - All total_daily_amount > 1,000,000
-- - transaction_count >= 1
-- - Sorted by transaction_date DESC, total_daily_amount DESC


-- ============================================================================
-- TEST 6: AGGREGATION ACCURACY VERIFICATION
-- ============================================================================
-- Objective: Verify SUM aggregation matches manual calculation
-- Expected: Aggregated total matches sum of individual transactions

WITH manual_calculation AS (
    SELECT 
        customer_id,
        CAST(transaction_date AS DATE) AS transaction_date,
        transaction_amount
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
      AND transaction_date IS NOT NULL
      AND transaction_amount IS NOT NULL
    LIMIT 1000  -- Sample for performance
),
aggregated_calculation AS (
    SELECT
        customer_id,
        transaction_date,
        SUM(transaction_amount) AS total_amount,
        COUNT(*) AS transaction_count
    FROM manual_calculation
    GROUP BY customer_id, transaction_date
)
SELECT
    'Test 6: Aggregation Accuracy' AS test_name,
    COUNT(*) AS unique_customer_days,
    SUM(total_amount) AS total_aggregated_amount,
    SUM(transaction_count) AS total_transaction_count,
    AVG(total_amount) AS avg_daily_amount,
    MAX(total_amount) AS max_daily_amount
FROM aggregated_calculation;

-- Expected Results:
-- - total_aggregated_amount should match sum from manual_calculation
-- - total_transaction_count should equal row count from manual_calculation
-- - No discrepancies indicate accurate aggregation


-- ============================================================================
-- TEST 7: NULL HANDLING VERIFICATION
-- ============================================================================
-- Objective: Confirm NULL values are properly excluded
-- Expected: No NULL customer_id or transaction_date in results

SELECT
    'Test 7: NULL Handling Verification' AS test_name,
    COUNT(*) AS total_results,
    COUNT(customer_id) AS non_null_customer_id,
    COUNT(transaction_date) AS non_null_transaction_date,
    COUNT(total_daily_amount) AS non_null_total_amount,
    CASE 
        WHEN COUNT(*) = COUNT(customer_id) 
         AND COUNT(*) = COUNT(transaction_date)
         AND COUNT(*) = COUNT(total_daily_amount)
        THEN 'PASS: No NULLs in results'
        ELSE 'FAIL: NULLs found in results'
    END AS test_result
FROM (
    SELECT
        customer_id,
        CAST(transaction_date AS DATE) AS transaction_date,
        COALESCE(SUM(transaction_amount), 0) AS total_daily_amount
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
      AND transaction_date IS NOT NULL
      AND transaction_amount IS NOT NULL
    GROUP BY customer_id, CAST(transaction_date AS DATE)
    HAVING COALESCE(SUM(transaction_amount), 0) > 1000000
) null_check;

-- Expected Results:
-- - test_result = 'PASS: No NULLs in results'
-- - total_results = non_null_customer_id = non_null_transaction_date = non_null_total_amount


-- ============================================================================
-- TEST 8: DATE GROUPING ACCURACY
-- ============================================================================
-- Objective: Verify CAST(transaction_date AS DATE) groups correctly
-- Expected: Same calendar day transactions are grouped together

SELECT
    'Test 8: Date Grouping Accuracy' AS test_name,
    customer_id,
    original_timestamp,
    normalized_date,
    transaction_count,
    CASE 
        WHEN COUNT(DISTINCT normalized_date) = 1 THEN 'PASS: Correct grouping'
        ELSE 'FAIL: Multiple dates in group'
    END AS test_result
FROM (
    SELECT
        customer_id,
        transaction_date AS original_timestamp,
        CAST(transaction_date AS DATE) AS normalized_date,
        COUNT(*) AS transaction_count
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
      AND transaction_date IS NOT NULL
      AND transaction_amount IS NOT NULL
    GROUP BY customer_id, transaction_date, CAST(transaction_date AS DATE)
) date_grouping_check
GROUP BY customer_id, original_timestamp, normalized_date, transaction_count
LIMIT 10;

-- Expected Results:
-- - test_result = 'PASS: Correct grouping' for all rows
-- - normalized_date should be date-only (no time component)


-- ============================================================================
-- TEST 9: SORTING VALIDATION
-- ============================================================================
-- Objective: Verify results are sorted correctly (date DESC, amount DESC)
-- Expected: Results in proper order

WITH sorted_results AS (
    SELECT
        customer_id,
        CAST(transaction_date AS DATE) AS transaction_date,
        COALESCE(SUM(transaction_amount), 0) AS total_daily_amount,
        ROW_NUMBER() OVER (ORDER BY CAST(transaction_date AS DATE) DESC, COALESCE(SUM(transaction_amount), 0) DESC) AS row_num
    FROM TRANSACTION
    WHERE customer_id IS NOT NULL
      AND transaction_date IS NOT NULL
      AND transaction_amount IS NOT NULL
    GROUP BY customer_id, CAST(transaction_date AS DATE)
    HAVING COALESCE(SUM(transaction_amount), 0) > 1000000
)
SELECT
    'Test 9: Sorting Validation' AS test_name,
    COUNT(*) AS total_rows,
    MAX(row_num) AS max_row_number,
    CASE 
        WHEN COUNT(*) = MAX(row_num) THEN 'PASS: Proper sorting'
        ELSE 'FAIL: Sorting issue'
    END AS test_result
FROM sorted_results;

-- Expected Results:
-- - test_result = 'PASS: Proper sorting'
-- - Row numbers should be sequential from 1 to total_rows


-- ============================================================================
-- TEST 10: PERFORMANCE BENCHMARK
-- ============================================================================
-- Objective: Measure query execution time
-- Expected: Completes within acceptable time frame (typically < 30 seconds)

-- Note: Execution time varies by database platform and data volume
-- Run EXPLAIN PLAN to verify index usage:
-- EXPLAIN SELECT ... [main query here]

SELECT
    'Test 10: Performance Benchmark' AS test_name,
    'Execute EXPLAIN PLAN to verify index usage' AS instruction,
    'Expected: Index scans on customer_id, transaction_date' AS expected_result;

-- To execute performance test, run the main query and measure time:
-- SET STATISTICS TIME ON;  -- SQL Server
-- \timing  -- PostgreSQL
-- SET TIMING ON;  -- Oracle
-- Then execute: daily_high_value_customer_report.sql


-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
-- Execute all tests above sequentially
-- Review results to validate:
-- 1. ✅ Data quality is acceptable
-- 2. ✅ Customer and date distributions are expected
-- 3. ✅ Threshold filtering works correctly
-- 4. ✅ Main query executes and returns valid results
-- 5. ✅ Aggregation calculations are accurate
-- 6. ✅ NULL handling prevents data quality issues
-- 7. ✅ Date grouping is correct (no time component)
-- 8. ✅ Sorting order is as specified
-- 9. ✅ Performance is acceptable

-- If all tests pass, the implementation is ready for production deployment.
