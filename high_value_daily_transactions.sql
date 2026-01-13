/*******************************************************************************
 * HIGH-VALUE TRANSACTION MONITORING - DAILY AGGREGATION QUERY
 *******************************************************************************
 * Purpose: Identify customers with daily transaction amounts exceeding $1M
 * Business Logic: Aggregate all transactions by customer and day, filter for
 *                 high-value activity to support fraud detection and compliance
 * Threshold: $1,000,000 per customer per day
 * Created: 2026-01-12
 * Modified: 2026-01-12 - Added INTERNAL transfer exclusion for revenue accuracy
 ******************************************************************************/

-- Index recommendations for query optimization
-- CREATE INDEX IF NOT EXISTS idx_transaction_customer_date
--     ON TRANSACTION(CUSTOMER_ID, TRANSACTION_DATE);
-- CREATE INDEX IF NOT EXISTS idx_account_customer
--     ON ACCOUNT(CUSTOMER_ID);
-- CREATE INDEX IF NOT EXISTS idx_transaction_transfer_type
--     ON TRANSACTION(TRANSFER_TYPE);

/*******************************************************************************
 * MAIN AGGREGATION QUERY
 * Groups transactions by customer and calendar day, filtering for amounts > 1M
 * Excludes INTERNAL transfers to ensure accurate revenue calculations
 ******************************************************************************/
SELECT 
    -- Customer identifier for tracking high-value activity
    a.CUSTOMER_ID,
    
    -- Transaction date normalized to calendar day (removes time component)
    -- This ensures all transactions within a 24-hour period are grouped together
    CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
    
    -- Total transaction amount for the customer on this specific day
    -- NULL values are excluded from SUM automatically by SQL standard
    SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT

FROM 
    TRANSACTION t
    
    -- Join with ACCOUNT to get customer association
    -- INNER JOIN ensures we only process transactions with valid accounts
    INNER JOIN ACCOUNT a 
        ON t.ACCOUNT_ID = a.ACCOUNT_ID

WHERE 
    -- Data quality filter: Exclude records with missing critical fields
    -- This prevents NULL values from affecting aggregation accuracy
    t.TRANSACTION_DATE IS NOT NULL
    AND t.AMOUNT IS NOT NULL
    AND a.CUSTOMER_ID IS NOT NULL
    
    -- Revenue accuracy filter: Exclude INTERNAL transfers
    -- INTERNAL transfers are internal movements between accounts and should not count toward revenue
    -- Include NULL transfer_type to maintain backward compatibility with legacy data
    AND (t.TRANSFER_TYPE <> 'INTERNAL' OR t.TRANSFER_TYPE IS NULL)
    
    -- Optional: Add date range filter for performance (uncomment if needed)
    -- AND t.TRANSACTION_DATE >= CURRENT_DATE - INTERVAL '90 days'

GROUP BY 
    -- Group by customer to aggregate all their transactions
    a.CUSTOMER_ID,
    
    -- Group by calendar day (not timestamp) to aggregate daily totals
    -- CAST ensures consistent date grouping regardless of time zones
    CAST(t.TRANSACTION_DATE AS DATE)

HAVING 
    -- Business rule: Filter for high-value daily activity exceeding $1M threshold
    -- HAVING is used (not WHERE) because it filters after aggregation
    SUM(t.AMOUNT) > 1000000

ORDER BY 
    -- Sort by date descending to show most recent high-value activity first
    TRANSACTION_DATE DESC,
    -- Then by amount descending to prioritize largest transactions
    TOTAL_DAILY_AMOUNT DESC;

/*******************************************************************************
 * QUERY NOTES AND CONSIDERATIONS
 *******************************************************************************
 * 
 * TIMEZONE HANDLING:
 * - CAST(TRANSACTION_DATE AS DATE) normalizes to UTC date by default
 * - If business logic requires local timezone:
 *   Replace with: DATE(CONVERT_TIMEZONE('America/New_York', TRANSACTION_DATE))
 * 
 * NULL HANDLING:
 * - WHERE clause explicitly filters NULL values before aggregation
 * - SUM() automatically excludes NULL amounts per SQL standard
 * - Ensures accurate aggregation and prevents unexpected results
 * 
 * TRANSFER TYPE FILTERING:
 * - INTERNAL transfers are excluded from revenue calculations
 * - NULL transfer_type values are included for backward compatibility
 * - If your data model guarantees non-NULL transfer_type, simplify to:
 *   AND t.TRANSFER_TYPE <> 'INTERNAL'
 * 
 * PERFORMANCE OPTIMIZATION:
 * - Recommended indexes on (CUSTOMER_ID, TRANSACTION_DATE) for fast lookups
 * - Additional index on TRANSFER_TYPE improves filter performance
 * - INNER JOIN on ACCOUNT ensures referential integrity
 * - Date filter in WHERE clause (if uncommented) limits scan range
 * 
 * EDGE CASES HANDLED:
 * - Customers with multiple accounts: All accounts aggregated per customer
 * - Same-day transactions across time zones: Normalized to calendar date
 * - Missing or invalid data: Filtered via WHERE clause NULL checks
 * - Negative amounts (refunds/reversals): Included in sum (can offset credits)
 * - INTERNAL transfers: Excluded to prevent double-counting in revenue
 * 
 * BUSINESS RULES:
 * - Threshold: $1,000,000 per customer per day (configurable in HAVING clause)
 * - Scope: External transactions only (excludes INTERNAL transfers)
 * - Aggregation level: By customer (not by account) for holistic view
 * 
 * ALTERNATIVE IMPLEMENTATIONS:
 * - For account-level aggregation: Remove ACCOUNT join, use t.ACCOUNT_ID directly
 * - For all transfers including internal: Remove TRANSFER_TYPE filter
 * - For specific transaction types: Add WHERE TRANSACTION_TYPE IN (...) filter
 ******************************************************************************/
