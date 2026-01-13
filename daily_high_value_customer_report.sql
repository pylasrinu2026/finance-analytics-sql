/*******************************************************************************
 * DAILY HIGH-VALUE CUSTOMER TRANSACTION ANALYSIS QUERY
 *******************************************************************************
 * Purpose: Identify customers with daily transaction amounts exceeding $1M
 * Business Logic: Aggregate all customer transactions by customer ID and date,
 *                 calculate daily totals, and filter for high-value activity
 * Threshold: $1,000,000 per customer per day
 * Created: 2026-01-13
 * 
 * Assumptions:
 * - Source table includes: transaction_id, customer_id, transaction_date, 
 *   transaction_amount fields
 * - customer_id is directly available in the transaction table
 ******************************************************************************/

-- ============================================================================
-- PERFORMANCE OPTIMIZATION: INDEX RECOMMENDATIONS
-- ============================================================================
-- Execute these CREATE INDEX statements for optimal query performance:
--
-- CREATE INDEX IF NOT EXISTS idx_transaction_customer_date 
--     ON TRANSACTION(customer_id, transaction_date);
--
-- CREATE INDEX IF NOT EXISTS idx_transaction_amount 
--     ON TRANSACTION(transaction_amount) 
--     WHERE transaction_amount IS NOT NULL;
--
-- CREATE INDEX IF NOT EXISTS idx_transaction_composite
--     ON TRANSACTION(customer_id, transaction_date, transaction_amount);
-- ============================================================================

/*******************************************************************************
 * MAIN QUERY: DAILY HIGH-VALUE CUSTOMER TRANSACTION AGGREGATION
 * 
 * This query performs the following operations:
 * 1. Groups all transactions by customer_id and transaction_date
 * 2. Calculates SUM of transaction amounts per customer per day
 * 3. Counts number of transactions per customer per day
 * 4. Filters results to show only days where total exceeds $1,000,000
 * 5. Handles NULL values and edge cases appropriately
 * 6. Sorts results by date (DESC) and amount (DESC) for report readability
 ******************************************************************************/

SELECT
    -- Customer identifier for tracking high-value activity
    customer_id AS customer_id,
    
    -- Transaction date normalized to calendar day (removes time component)
    -- This ensures all transactions within a 24-hour period are grouped together
    CAST(transaction_date AS DATE) AS transaction_date,
    
    -- Total transaction amount for the customer on this specific day
    -- NULL values are automatically excluded from SUM per SQL standard
    -- COALESCE ensures result is never NULL (defaults to 0 if no valid amounts)
    COALESCE(SUM(transaction_amount), 0) AS total_daily_amount,
    
    -- Count of individual transactions for the customer on this day
    -- Excludes NULL transaction amounts to count only valid transactions
    COUNT(CASE WHEN transaction_amount IS NOT NULL THEN 1 END) AS transaction_count,
    
    -- Average transaction amount for the day (useful for identifying patterns)
    -- Returns NULL if no valid transactions exist
    AVG(transaction_amount) AS average_transaction_amount,
    
    -- Highest single transaction amount for the day
    -- Useful for identifying exceptionally large individual transactions
    MAX(transaction_amount) AS max_transaction_amount,
    
    -- Lowest transaction amount for the day
    -- Helps identify the transaction range
    MIN(transaction_amount) AS min_transaction_amount

FROM
    TRANSACTION

WHERE
    -- Data quality filter: Exclude records with missing critical fields
    -- This prevents NULL values from affecting aggregation accuracy
    customer_id IS NOT NULL
    AND transaction_date IS NOT NULL
    AND transaction_amount IS NOT NULL
    
    -- Edge case handling: Exclude zero or negative amounts if business rules require
    -- Uncomment the following line to enforce positive amounts only:
    -- AND transaction_amount > 0
    
    -- Optional: Date range filter for performance optimization
    -- Uncomment and adjust as needed for specific reporting periods:
    -- AND transaction_date >= CURRENT_DATE - INTERVAL '90 days'
    -- AND transaction_date < CURRENT_DATE

GROUP BY
    -- Group by customer to aggregate all their transactions
    customer_id,
    
    -- Group by calendar day (not timestamp) to aggregate daily totals
    -- CAST ensures consistent date grouping regardless of time zones
    CAST(transaction_date AS DATE)

HAVING
    -- Business rule: Filter for high-value daily activity exceeding $1M threshold
    -- HAVING clause is used (not WHERE) because it filters AFTER aggregation
    -- COALESCE ensures NULL-safe comparison (treats NULL as 0)
    COALESCE(SUM(transaction_amount), 0) > 1000000

ORDER BY
    -- Primary sort: Most recent activity first (descending date order)
    transaction_date DESC,
    
    -- Secondary sort: Highest transaction amounts first
    -- Prioritizes customers with largest daily totals
    total_daily_amount DESC,
    
    -- Tertiary sort: Customer ID for consistent ordering when amounts are equal
    customer_id ASC;

/*******************************************************************************
 * QUERY NOTES AND CONSIDERATIONS
 *******************************************************************************
 *
 * TIMEZONE HANDLING:
 * - CAST(transaction_date AS DATE) normalizes to UTC date by default
 * - If business logic requires local timezone conversion:
 *   Replace with: DATE(CONVERT_TIMEZONE('America/New_York', transaction_date))
 *   Or use database-specific timezone functions
 *
 * NULL HANDLING STRATEGY:
 * - WHERE clause filters out NULL customer_id, transaction_date, and amounts
 * - SUM() automatically excludes NULL amounts per SQL standard
 * - COALESCE(SUM(...), 0) ensures result is never NULL
 * - COUNT with CASE WHEN filters only non-NULL amounts
 * - This multi-layer approach ensures accurate aggregation
 *
 * EDGE CASES HANDLED:
 * - Zero amounts: Currently included; add filter if business requires positive only
 * - Negative amounts: Currently included; may represent refunds/reversals
 * - Same-day multiple transactions: All aggregated into single daily total
 * - Missing customer_id: Filtered out to prevent aggregation errors
 * - Date-only vs datetime: CAST to DATE ensures consistent grouping
 *
 * PERFORMANCE OPTIMIZATION TIPS:
 * 1. Create recommended composite indexes (see top of file)
 * 2. Add date range filter if analyzing specific periods
 * 3. Consider partitioning TRANSACTION table by transaction_date
 * 4. Use EXPLAIN PLAN to verify index usage
 * 5. For very large datasets, consider materialized views
 *
 * BUSINESS LOGIC VARIATIONS:
 * - To change threshold: Modify HAVING clause (currently > 1000000)
 * - To exclude refunds: Add WHERE transaction_amount > 0
 * - To include customer details: JOIN with CUSTOMER table on customer_id
 * - To filter by transaction type: Add WHERE transaction_type = 'specific_type'
 * - To group by week/month: Adjust GROUP BY to use DATEPART or DATE_TRUNC
 *
 * OUTPUT SCHEMA:
 * - customer_id: STRING - Customer unique identifier
 * - transaction_date: DATE - Calendar date of transactions
 * - total_daily_amount: NUMBER(18,2) - Sum of all transaction amounts
 * - transaction_count: INTEGER - Number of transactions for the day
 * - average_transaction_amount: NUMBER(18,2) - Mean transaction amount
 * - max_transaction_amount: NUMBER(18,2) - Largest single transaction
 * - min_transaction_amount: NUMBER(18,2) - Smallest single transaction
 *
 * USAGE EXAMPLES:
 * 
 * 1. Basic execution (as-is):
 *    Simply run this entire query to get all high-value customers
 * 
 * 2. Filter for specific date range:
 *    Add to WHERE clause:
 *    AND transaction_date BETWEEN '2026-01-01' AND '2026-01-31'
 * 
 * 3. Create view for recurring reports:
 *    CREATE OR REPLACE VIEW vw_daily_high_value_customers AS
 *    [this entire query]
 * 
 * 4. Export to reporting tool:
 *    This query output is ready for direct consumption by BI tools,
 *    CSV export, or integration with monitoring dashboards
 *
 ******************************************************************************/

-- ============================================================================
-- VALIDATION QUERIES (Optional - for testing and verification)
-- ============================================================================

-- Query 1: Check total transaction volume before aggregation
-- SELECT COUNT(*) as total_transactions,
--        COUNT(DISTINCT customer_id) as unique_customers,
--        SUM(transaction_amount) as total_amount
-- FROM TRANSACTION
-- WHERE customer_id IS NOT NULL 
--   AND transaction_date IS NOT NULL 
--   AND transaction_amount IS NOT NULL;

-- Query 2: Verify threshold logic
-- SELECT customer_id, 
--        CAST(transaction_date AS DATE) as transaction_date,
--        SUM(transaction_amount) as daily_total
-- FROM TRANSACTION
-- WHERE customer_id IS NOT NULL 
--   AND transaction_date IS NOT NULL 
--   AND transaction_amount IS NOT NULL
-- GROUP BY customer_id, CAST(transaction_date AS DATE)
-- ORDER BY daily_total DESC
-- LIMIT 10;

-- Query 3: Check for data quality issues
-- SELECT 
--     COUNT(*) as total_rows,
--     COUNT(customer_id) as non_null_customer_id,
--     COUNT(transaction_date) as non_null_date,
--     COUNT(transaction_amount) as non_null_amount,
--     COUNT(CASE WHEN transaction_amount <= 0 THEN 1 END) as zero_or_negative
-- FROM TRANSACTION;
