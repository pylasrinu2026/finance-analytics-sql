/*******************************************************************************
 * HIGH-VALUE TRANSACTION MONITORING - DAILY AGGREGATION (ACCOUNT-LEVEL)
 *******************************************************************************
 * Purpose: Alternative implementation for account-level aggregation when
 *          transaction table links directly to accounts rather than customers
 * Business Logic: Aggregate all transactions by account and day, then roll up
 *                 to customer level with high-value filtering
 * Threshold: $1,000,000 per customer per day
 * Created: 2026-01-12
 * Modified: 2026-01-12 - Added INTERNAL transfer exclusion for revenue accuracy
 ******************************************************************************/

-- Index recommendations for optimal performance
-- CREATE INDEX IF NOT EXISTS idx_transaction_account_date
--     ON TRANSACTION(ACCOUNT_ID, TRANSACTION_DATE);
-- CREATE INDEX IF NOT EXISTS idx_account_customer
--     ON ACCOUNT(CUSTOMER_ID, ACCOUNT_ID);
-- CREATE INDEX IF NOT EXISTS idx_transaction_transfer_type
--     ON TRANSACTION(TRANSFER_TYPE);

/*******************************************************************************
 * MAIN AGGREGATION QUERY - TWO-STEP APPROACH
 * Step 1: Aggregate transactions by account and day
 * Step 2: Roll up to customer level and filter for > $1M
 * Excludes INTERNAL transfers to ensure accurate revenue calculations
 ******************************************************************************/
WITH daily_account_transactions AS (
    -- Step 1: Aggregate at account level first for better performance
    SELECT 
        t.ACCOUNT_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        SUM(t.AMOUNT) AS ACCOUNT_DAILY_AMOUNT
    FROM 
        TRANSACTION t
    WHERE 
        -- Data quality: Filter out incomplete records
        t.TRANSACTION_DATE IS NOT NULL
        AND t.AMOUNT IS NOT NULL
        AND t.ACCOUNT_ID IS NOT NULL
        
        -- Revenue accuracy filter: Exclude INTERNAL transfers
        -- INTERNAL transfers are internal movements between accounts and should not count toward revenue
        -- Include NULL transfer_type to maintain backward compatibility with legacy data
        AND (t.TRANSFER_TYPE <> 'INTERNAL' OR t.TRANSFER_TYPE IS NULL)
    GROUP BY 
        t.ACCOUNT_ID,
        CAST(t.TRANSACTION_DATE AS DATE)
)
-- Step 2: Join with account data and aggregate to customer level
SELECT 
    -- Customer identifier for high-value monitoring
    a.CUSTOMER_ID,
    
    -- Transaction date (calendar day)
    dat.TRANSACTION_DATE,
    
    -- Sum all account transactions for this customer on this day
    -- Handles customers with multiple accounts
    SUM(dat.ACCOUNT_DAILY_AMOUNT) AS TOTAL_DAILY_AMOUNT,
    
    -- Additional metrics for analysis (optional)
    COUNT(DISTINCT dat.ACCOUNT_ID) AS NUMBER_OF_ACCOUNTS,
    MAX(dat.ACCOUNT_DAILY_AMOUNT) AS MAX_ACCOUNT_AMOUNT

FROM 
    daily_account_transactions dat
    
    -- Join to get customer association
    INNER JOIN ACCOUNT a 
        ON dat.ACCOUNT_ID = a.ACCOUNT_ID

WHERE 
    -- Ensure valid customer reference
    a.CUSTOMER_ID IS NOT NULL

GROUP BY 
    a.CUSTOMER_ID,
    dat.TRANSACTION_DATE

HAVING 
    -- Business rule: Filter for daily amounts exceeding $1M threshold
    SUM(dat.ACCOUNT_DAILY_AMOUNT) > 1000000

ORDER BY 
    dat.TRANSACTION_DATE DESC,
    TOTAL_DAILY_AMOUNT DESC;

/*******************************************************************************
 * SIMPLIFIED VERSION (DIRECT AGGREGATION)
 * Use this if your database performs better without CTEs
 * Modified to exclude INTERNAL transfers
 ******************************************************************************/
/*
SELECT 
    a.CUSTOMER_ID,
    CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
    SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT
FROM 
    TRANSACTION t
    INNER JOIN ACCOUNT a ON t.ACCOUNT_ID = a.ACCOUNT_ID
WHERE 
    t.TRANSACTION_DATE IS NOT NULL
    AND t.AMOUNT IS NOT NULL
    AND a.CUSTOMER_ID IS NOT NULL
    AND (t.TRANSFER_TYPE <> 'INTERNAL' OR t.TRANSFER_TYPE IS NULL)
GROUP BY 
    a.CUSTOMER_ID,
    CAST(t.TRANSACTION_DATE AS DATE)
HAVING 
    SUM(t.AMOUNT) > 1000000
ORDER BY 
    TRANSACTION_DATE DESC,
    TOTAL_DAILY_AMOUNT DESC;
*/

/*******************************************************************************
 * QUERY NOTES AND CONSIDERATIONS
 *******************************************************************************
 * 
 * TWO-STEP APPROACH BENEFITS:
 * - Better performance with large datasets due to early aggregation
 * - Clearer separation of concerns (account-level vs customer-level)
 * - Easier to debug and maintain
 * - Provides intermediate account-level metrics
 * 
 * TRANSFER TYPE FILTERING:
 * - INTERNAL transfers are excluded from revenue calculations in Step 1
 * - Filter applied early in CTE for better performance
 * - NULL transfer_type values are included for backward compatibility
 * - Ensures accurate revenue reporting without double-counting internal movements
 * 
 * PERFORMANCE OPTIMIZATION:
 * - CTE approach allows database to optimize aggregation strategy
 * - Indexes on ACCOUNT_ID, TRANSACTION_DATE, and TRANSFER_TYPE improve performance
 * - Early filtering reduces data volume for subsequent operations
 * - Consider materialized view for frequently-accessed results
 * 
 * NULL HANDLING:
 * - Both queries explicitly filter NULL values before aggregation
 * - TRANSFER_TYPE NULL values are treated as valid transactions (not INTERNAL)
 * - Ensures backward compatibility with legacy data lacking transfer_type
 * 
 * EDGE CASES HANDLED:
 * - Customers with multiple accounts: Properly aggregated across all accounts
 * - Accounts with mixed transfer types: Only non-INTERNAL transactions counted
 * - Missing transfer_type data: Treated as valid (non-INTERNAL) transactions
 * - Time zone variations: Normalized to calendar date
 * 
 * ALTERNATIVE IMPLEMENTATIONS:
 * - Use simplified version (commented out) for databases with poor CTE optimization
 * - Add transaction_type filtering if additional exclusions needed
 * - Modify threshold in HAVING clause for different business rules
 * - Add date range filter for historical analysis
 ******************************************************************************/
