/*******************************************************************************
 * HIGH-VALUE TRANSACTION REPORT VIEW
 *******************************************************************************
 * Object Name: vw_high_value_transactions_report
 * Purpose: Encapsulates daily transaction aggregation logic for compliance
 *          and risk monitoring of high-value customer activity (>$1M/day)
 * 
 * Business Use Case:
 *   - Compliance monitoring for anti-money laundering (AML) regulations
 *   - Risk assessment for customers with large daily transaction volumes
 *   - Executive dashboard reporting on high-value client activity
 *   - Fraud detection and investigation support
 * 
 * Created: 2026-01-12
 * Modified: 2026-01-12 - Added INTERNAL transfer exclusion for revenue accuracy
 * Target Framework: SQL (Snowflake/PostgreSQL compatible)
 *******************************************************************************
 *
 * COLUMN DEFINITIONS:
 * -------------------
 * priority_rank          : Ranking by total daily amount (1 = highest priority)
 * customer_id            : Unique customer identifier
 * customer_name          : Customer full name for reporting
 * customer_risk_level    : Customer type used as risk level indicator
 * account_count          : Number of accounts involved in high-value transactions
 * primary_account_number : First account number (for reference)
 * transaction_date       : Calendar date of aggregated transactions
 * transaction_count      : Number of transactions on this date
 * total_daily_amount     : Sum of all transaction amounts for the day
 * avg_transaction_amount : Average transaction size for the day
 * max_single_transaction : Largest individual transaction amount
 * report_generated_timestamp : Timestamp when view was queried
 * days_since_last_high_value : Days between current and previous high-value date
 * 
 * INDEXING RECOMMENDATIONS:
 * -------------------------
 * CREATE INDEX idx_transaction_customer_date 
 *     ON TRANSACTION(ACCOUNT_ID, TRANSACTION_DATE, AMOUNT);
 * CREATE INDEX idx_transaction_transfer_type
 *     ON TRANSACTION(TRANSFER_TYPE)
 *     WHERE TRANSFER_TYPE IS NOT NULL;
 * CREATE INDEX idx_account_customer 
 *     ON ACCOUNT(CUSTOMER_ID, ACCOUNT_ID);
 * CREATE INDEX idx_customer_type 
 *     ON CUSTOMER(CUSTOMER_ID, CUSTOMER_TYPE);
 *
 ******************************************************************************/

CREATE OR REPLACE VIEW vw_high_value_transactions_report AS

WITH daily_transaction_aggregates AS (
    /***************************************************************************
     * STEP 1: Aggregate transactions by customer and day
     * - Groups all transactions at customer level (across all accounts)
     * - Calculates daily totals, counts, and statistics
     * - Filters for high-value activity exceeding $1M threshold
     * - Excludes INTERNAL transfers for accurate revenue reporting
     ***************************************************************************/
    SELECT
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
        
        -- Aggregation metrics for compliance analysis
        COUNT(t.TRANSACTION_ID) AS TRANSACTION_COUNT,
        SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT,
        AVG(t.AMOUNT) AS AVG_TRANSACTION_AMOUNT,
        MAX(t.AMOUNT) AS MAX_SINGLE_TRANSACTION,
        
        -- Account information for reporting
        COUNT(DISTINCT a.ACCOUNT_ID) AS ACCOUNT_COUNT,
        MIN(a.ACCOUNT_ID) AS PRIMARY_ACCOUNT_NUMBER  -- First account as reference
        
    FROM TRANSACTION t
    INNER JOIN ACCOUNT a
        ON t.ACCOUNT_ID = a.ACCOUNT_ID
    WHERE
        -- Data quality filters
        t.TRANSACTION_DATE IS NOT NULL
        AND t.AMOUNT IS NOT NULL
        AND a.CUSTOMER_ID IS NOT NULL
        
        -- Revenue accuracy filter: Exclude INTERNAL transfers
        -- INTERNAL transfers are internal movements between accounts and should not count toward revenue
        -- Include NULL transfer_type to maintain backward compatibility with legacy data
        AND (t.TRANSFER_TYPE <> 'INTERNAL' OR t.TRANSFER_TYPE IS NULL)
        
    GROUP BY
        a.CUSTOMER_ID,
        CAST(t.TRANSACTION_DATE AS DATE)
        
    HAVING
        -- High-value threshold: $1M+ daily activity
        SUM(t.AMOUNT) > 1000000
),

customer_enriched AS (
    /***************************************************************************
     * STEP 2: Enrich with customer master data
     * - Adds customer name and type (risk level proxy)
     * - Provides business context for compliance review
     ***************************************************************************/
    SELECT
        dta.*,
        c.CUSTOMER_NAME,
        c.CUSTOMER_TYPE AS CUSTOMER_RISK_LEVEL,  -- Customer type as risk indicator
        c.COUNTRY
    FROM daily_transaction_aggregates dta
    INNER JOIN CUSTOMER c
        ON dta.CUSTOMER_ID = c.CUSTOMER_ID
),

ranked_transactions AS (
    /***************************************************************************
     * STEP 3: Add prioritization and temporal metrics
     * - Ranks by total daily amount (highest priority first)
     * - Calculates days since last high-value transaction event
     ***************************************************************************/
    SELECT
        ce.*,
        
        -- Priority ranking for compliance review queue
        ROW_NUMBER() OVER (
            ORDER BY ce.TOTAL_DAILY_AMOUNT DESC, ce.TRANSACTION_DATE DESC
        ) AS PRIORITY_RANK,
        
        -- Temporal analysis: Days between high-value transaction events
        DATEDIFF(
            day,
            LAG(ce.TRANSACTION_DATE) OVER (
                PARTITION BY ce.CUSTOMER_ID 
                ORDER BY ce.TRANSACTION_DATE
            ),
            ce.TRANSACTION_DATE
        ) AS DAYS_SINCE_LAST_HIGH_VALUE,
        
        -- Report generation timestamp for audit trail
        CURRENT_TIMESTAMP AS REPORT_GENERATED_TIMESTAMP
        
    FROM customer_enriched ce
)

/*******************************************************************************
 * FINAL OUTPUT
 * - Structured for consumption by reporting tools
 * - Ordered by priority (highest value first)
 ******************************************************************************/
SELECT
    -- Prioritization columns
    PRIORITY_RANK,
    
    -- Customer identification
    CUSTOMER_ID,
    CUSTOMER_NAME,
    CUSTOMER_RISK_LEVEL,
    COUNTRY,
    
    -- Account information
    ACCOUNT_COUNT,
    PRIMARY_ACCOUNT_NUMBER,
    
    -- Transaction date and metrics
    TRANSACTION_DATE,
    TRANSACTION_COUNT,
    TOTAL_DAILY_AMOUNT,
    AVG_TRANSACTION_AMOUNT,
    MAX_SINGLE_TRANSACTION,
    
    -- Temporal analysis
    DAYS_SINCE_LAST_HIGH_VALUE,
    
    -- Metadata
    REPORT_GENERATED_TIMESTAMP

FROM ranked_transactions

ORDER BY PRIORITY_RANK;

/*******************************************************************************
 * USAGE EXAMPLES
 *******************************************************************************
 *
 * Example 1: Get top 10 highest-value transactions for dashboard
 * ----------------------------------------------------------------
 * SELECT * 
 * FROM vw_high_value_transactions_report
 * WHERE TRANSACTION_DATE >= CURRENT_DATE - 30
 * LIMIT 10;
 *
 * Example 2: Filter by customer risk level for targeted review
 * --------------------------------------------------------------
 * SELECT 
 *     CUSTOMER_NAME,
 *     TRANSACTION_DATE,
 *     TOTAL_DAILY_AMOUNT,
 *     TRANSACTION_COUNT
 * FROM vw_high_value_transactions_report
 * WHERE CUSTOMER_RISK_LEVEL = 'HIGH_RISK'
 * ORDER BY TRANSACTION_DATE DESC;
 *
 * Example 3: Identify customers with frequent high-value activity
 * -----------------------------------------------------------------
 * SELECT 
 *     CUSTOMER_ID,
 *     CUSTOMER_NAME,
 *     COUNT(*) AS HIGH_VALUE_DAYS,
 *     AVG(DAYS_SINCE_LAST_HIGH_VALUE) AS AVG_FREQUENCY_DAYS
 * FROM vw_high_value_transactions_report
 * WHERE TRANSACTION_DATE >= CURRENT_DATE - 90
 * GROUP BY CUSTOMER_ID, CUSTOMER_NAME
 * HAVING COUNT(*) >= 5  -- 5+ high-value days in 90-day period
 * ORDER BY HIGH_VALUE_DAYS DESC;
 *
 * Example 4: Export for compliance reporting system
 * ---------------------------------------------------
 * SELECT 
 *     CUSTOMER_ID,
 *     CUSTOMER_NAME,
 *     TRANSACTION_DATE,
 *     TOTAL_DAILY_AMOUNT,
 *     TRANSACTION_COUNT,
 *     ACCOUNT_COUNT,
 *     CUSTOMER_RISK_LEVEL,
 *     REPORT_GENERATED_TIMESTAMP
 * FROM vw_high_value_transactions_report
 * WHERE TRANSACTION_DATE BETWEEN '2026-01-01' AND '2026-01-31'
 * ORDER BY TRANSACTION_DATE DESC, TOTAL_DAILY_AMOUNT DESC;
 *
 ******************************************************************************/

/*******************************************************************************
 * PERFORMANCE NOTES
 *******************************************************************************
 * 
 * Expected Performance:
 * - Query execution time: < 5 seconds for 1M+ transaction records
 * - View materialization: Consider creating materialized view for large datasets
 * - Refresh frequency: Recommended daily refresh for compliance reporting
 * 
 * Optimization Tips:
 * - Apply date filters in WHERE clause when querying the view
 * - Use LIMIT clause for dashboard displays to reduce result set
 * - Consider partitioning TRANSACTION table by TRANSACTION_DATE
 * - Monitor query plans and adjust indexes based on actual usage patterns
 * - TRANSFER_TYPE filter reduces data volume early in query execution
 * 
 * Materialized View Alternative (for better performance):
 * CREATE MATERIALIZED VIEW mv_high_value_transactions_report AS
 * SELECT * FROM vw_high_value_transactions_report;
 * 
 * -- Refresh daily at 2 AM
 * CREATE TASK refresh_high_value_report
 *   WAREHOUSE = COMPLIANCE_WH
 *   SCHEDULE = 'USING CRON 0 2 * * * UTC'
 * AS
 *   REFRESH MATERIALIZED VIEW mv_high_value_transactions_report;
 *
 ******************************************************************************/
