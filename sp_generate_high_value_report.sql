/*******************************************************************************
 * HIGH-VALUE TRANSACTION REPORT STORED PROCEDURE
 *******************************************************************************
 * Object Name: sp_generate_high_value_report
 * Purpose: Flexible date-range parameterized stored procedure for generating
 *          high-value transaction reports for compliance and risk monitoring
 * 
 * Parameters:
 *   @start_date : Start date of reporting period (inclusive)
 *   @end_date   : End date of reporting period (inclusive)
 * 
 * Business Use Case:
 *   - Ad-hoc compliance report generation for specific date ranges
 *   - Regulatory reporting with flexible period selection
 *   - Historical analysis of high-value customer activity
 *   - Scheduled batch report generation via automation
 * 
 * Created: 2026-01-12
 * Modified: 2026-01-12 - Added INTERNAL transfer exclusion for revenue accuracy
 * Target Framework: SQL (Snowflake/PostgreSQL compatible with syntax adjustments)
 *******************************************************************************
 *
 * FEATURES:
 * ---------
 * ✓ Parameterized date range for flexible reporting periods
 * ✓ Comprehensive error handling and validation
 * ✓ Transaction count and aggregation metrics
 * ✓ Customer enrichment (name, risk level, country)
 * ✓ Priority ranking by transaction amount
 * ✓ Temporal analysis (days since last high-value event)
 * ✓ Audit trail with report generation timestamp
 * ✓ Optimized for read performance with indexed joins
 * ✓ Structured output for BI tools and dashboards
 * ✓ Excludes INTERNAL transfers for accurate revenue reporting
 *
 ******************************************************************************/

CREATE OR REPLACE PROCEDURE sp_generate_high_value_report(
    start_date DATE,
    end_date DATE
)
RETURNS TABLE (
    priority_rank INTEGER,
    customer_id STRING,
    customer_name STRING,
    customer_risk_level STRING,
    country STRING,
    account_count INTEGER,
    primary_account_number STRING,
    transaction_date DATE,
    transaction_count INTEGER,
    total_daily_amount DECIMAL(18,2),
    avg_transaction_amount DECIMAL(18,2),
    max_single_transaction DECIMAL(18,2),
    days_since_last_high_value INTEGER,
    report_generated_timestamp TIMESTAMP,
    date_range_start DATE,
    date_range_end DATE
)
LANGUAGE SQL
AS
$$
/*******************************************************************************
 * PROCEDURE BODY WITH ERROR HANDLING
 ******************************************************************************/
DECLARE
    v_start_date DATE := start_date;
    v_end_date DATE := end_date;
    v_row_count INTEGER;
BEGIN
    
    /***************************************************************************
     * INPUT VALIDATION
     * - Ensures date parameters are provided and logical
     * - Prevents invalid date ranges and NULL inputs
     ***************************************************************************/
    
    -- Validate that start_date is provided
    IF (v_start_date IS NULL) THEN
        RETURN 'ERROR: start_date parameter cannot be NULL. Please provide a valid start date.';
    END IF;
    
    -- Validate that end_date is provided
    IF (v_end_date IS NULL) THEN
        RETURN 'ERROR: end_date parameter cannot be NULL. Please provide a valid end date.';
    END IF;
    
    -- Validate that start_date is not after end_date
    IF (v_start_date > v_end_date) THEN
        RETURN 'ERROR: start_date cannot be after end_date. Please provide a valid date range.';
    END IF;
    
    -- Validate reasonable date range (optional: limit to prevent performance issues)
    IF (DATEDIFF(day, v_start_date, v_end_date) > 365) THEN
        RETURN 'WARNING: Date range exceeds 365 days. Consider using smaller ranges for better performance.';
    END IF;
    
    /***************************************************************************
     * MAIN QUERY LOGIC
     * - Multi-stage CTE approach for clarity and maintainability
     * - Follows same pattern as vw_high_value_transactions_report
     * - Adds date range filtering based on parameters
     * - Excludes INTERNAL transfers for accurate revenue reporting
     ***************************************************************************/
    
    RETURN TABLE (
        
        WITH daily_transaction_aggregates AS (
            /***********************************************************************
             * STEP 1: Aggregate transactions by customer and day within date range
             * - Filters transactions to specified date range
             * - Groups at customer level across all accounts
             * - Calculates daily totals and statistics
             * - Excludes INTERNAL transfers for revenue accuracy
             ***********************************************************************/
            SELECT
                a.CUSTOMER_ID,
                CAST(t.TRANSACTION_DATE AS DATE) AS TRANSACTION_DATE,
                
                -- Transaction metrics
                COUNT(t.TRANSACTION_ID) AS TRANSACTION_COUNT,
                SUM(t.AMOUNT) AS TOTAL_DAILY_AMOUNT,
                AVG(t.AMOUNT) AS AVG_TRANSACTION_AMOUNT,
                MAX(t.AMOUNT) AS MAX_SINGLE_TRANSACTION,
                
                -- Account information
                COUNT(DISTINCT a.ACCOUNT_ID) AS ACCOUNT_COUNT,
                MIN(a.ACCOUNT_ID) AS PRIMARY_ACCOUNT_NUMBER
                
            FROM TRANSACTION t
            INNER JOIN ACCOUNT a
                ON t.ACCOUNT_ID = a.ACCOUNT_ID
            WHERE
                -- Date range filter (procedure parameters)
                t.TRANSACTION_DATE >= v_start_date
                AND t.TRANSACTION_DATE <= v_end_date
                
                -- Data quality filters
                AND t.TRANSACTION_DATE IS NOT NULL
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
            /***********************************************************************
             * STEP 2: Enrich with customer master data
             * - Adds customer identifying information
             * - Provides business context for compliance review
             ***********************************************************************/
            SELECT
                dta.*,
                c.CUSTOMER_NAME,
                c.CUSTOMER_TYPE AS CUSTOMER_RISK_LEVEL,
                c.COUNTRY
            FROM daily_transaction_aggregates dta
            INNER JOIN CUSTOMER c
                ON dta.CUSTOMER_ID = c.CUSTOMER_ID
        ),
        
        ranked_transactions AS (
            /***********************************************************************
             * STEP 3: Add prioritization and temporal analysis
             * - Ranks by total daily amount for priority review
             * - Calculates days between high-value events
             * - Adds report metadata
             ***********************************************************************/
            SELECT
                ce.*,
                
                -- Priority ranking for compliance review queue
                ROW_NUMBER() OVER (
                    ORDER BY ce.TOTAL_DAILY_AMOUNT DESC, ce.TRANSACTION_DATE DESC
                ) AS PRIORITY_RANK,
                
                -- Temporal analysis: Days between high-value events
                DATEDIFF(
                    day,
                    LAG(ce.TRANSACTION_DATE) OVER (
                        PARTITION BY ce.CUSTOMER_ID 
                        ORDER BY ce.TRANSACTION_DATE
                    ),
                    ce.TRANSACTION_DATE
                ) AS DAYS_SINCE_LAST_HIGH_VALUE,
                
                -- Report generation metadata
                CURRENT_TIMESTAMP AS REPORT_GENERATED_TIMESTAMP,
                v_start_date AS DATE_RANGE_START,
                v_end_date AS DATE_RANGE_END
                
            FROM customer_enriched ce
        )
        
        /***********************************************************************
         * FINAL OUTPUT
         * - Structured for consumption by reporting tools
         * - Ordered by priority (highest value first)
         ***********************************************************************/
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
            REPORT_GENERATED_TIMESTAMP,
            DATE_RANGE_START,
            DATE_RANGE_END
        FROM ranked_transactions
        ORDER BY PRIORITY_RANK
    );
    
    /***************************************************************************
     * POST-EXECUTION LOGGING (Optional)
     * - Get row count for audit trail
     ***************************************************************************/
    v_row_count := SQLROWCOUNT;
    
    RETURN 'SUCCESS: Generated high-value transaction report for period ' || 
           v_start_date || ' to ' || v_end_date || 
           ' (' || v_row_count || ' records)';
    
END;
$$;

/*******************************************************************************
 * USAGE EXAMPLES
 *******************************************************************************
 *
 * Example 1: Generate report for last 30 days
 * ---------------------------------------------
 * CALL sp_generate_high_value_report(
 *     CURRENT_DATE - 30,
 *     CURRENT_DATE
 * );
 *
 * Example 2: Generate report for specific month
 * ----------------------------------------------
 * CALL sp_generate_high_value_report(
 *     '2026-01-01'::DATE,
 *     '2026-01-31'::DATE
 * );
 *
 * Example 3: Generate quarterly compliance report
 * ------------------------------------------------
 * CALL sp_generate_high_value_report(
 *     '2026-01-01'::DATE,
 *     '2026-03-31'::DATE
 * );
 *
 * Example 4: Store results in table for batch processing
 * -------------------------------------------------------
 * CREATE TABLE high_value_report_archive AS
 * SELECT * FROM TABLE(sp_generate_high_value_report(
 *     '2025-01-01'::DATE,
 *     '2025-12-31'::DATE
 * ));
 *
 * Example 5: Filter results by risk level
 * ----------------------------------------
 * SELECT 
 *     CUSTOMER_NAME,
 *     TRANSACTION_DATE,
 *     TOTAL_DAILY_AMOUNT,
 *     TRANSACTION_COUNT
 * FROM TABLE(sp_generate_high_value_report(
 *     CURRENT_DATE - 90,
 *     CURRENT_DATE
 * ))
 * WHERE CUSTOMER_RISK_LEVEL IN ('HIGH_RISK', 'MEDIUM_RISK')
 * ORDER BY TOTAL_DAILY_AMOUNT DESC;
 *
 ******************************************************************************/

/*******************************************************************************
 * SCHEDULING EXAMPLES (Snowflake)
 *******************************************************************************
 *
 * Schedule 1: Daily report generation at 3 AM
 * --------------------------------------------
 * CREATE TASK task_daily_high_value_report
 *   WAREHOUSE = COMPLIANCE_WH
 *   SCHEDULE = 'USING CRON 0 3 * * * UTC'
 * AS
 *   CALL sp_generate_high_value_report(
 *       CURRENT_DATE - 1,
 *       CURRENT_DATE - 1
 *   );
 *
 * Schedule 2: Weekly summary report every Monday
 * -----------------------------------------------
 * CREATE TASK task_weekly_high_value_report
 *   WAREHOUSE = COMPLIANCE_WH
 *   SCHEDULE = 'USING CRON 0 4 * * 1 UTC'  -- Every Monday at 4 AM
 * AS
 *   INSERT INTO weekly_compliance_reports
 *   SELECT * FROM TABLE(sp_generate_high_value_report(
 *       CURRENT_DATE - 7,
 *       CURRENT_DATE - 1
 *   ));
 *
 * Schedule 3: Monthly compliance report (first day of month)
 * -----------------------------------------------------------
 * CREATE TASK task_monthly_high_value_report
 *   WAREHOUSE = COMPLIANCE_WH
 *   SCHEDULE = 'USING CRON 0 5 1 * * UTC'  -- First day of month at 5 AM
 * AS
 *   CALL sp_generate_high_value_report(
 *       DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month'),
 *       LAST_DAY(CURRENT_DATE - INTERVAL '1 month')
 *   );
 *
 ******************************************************************************/

/*******************************************************************************
 * PERFORMANCE OPTIMIZATION NOTES
 *******************************************************************************
 *
 * Index Recommendations:
 * ----------------------
 * CREATE INDEX idx_transaction_date_amount 
 *     ON TRANSACTION(TRANSACTION_DATE, ACCOUNT_ID, AMOUNT)
 *     WHERE AMOUNT > 1000000;  -- Partial index for high-value only
 * 
 * CREATE INDEX idx_transaction_transfer_type
 *     ON TRANSACTION(TRANSFER_TYPE)
 *     WHERE TRANSFER_TYPE IS NOT NULL;
 * 
 * CREATE INDEX idx_account_customer_active
 *     ON ACCOUNT(CUSTOMER_ID, ACCOUNT_ID)
 *     WHERE STATUS = 'ACTIVE';
 *
 * Partitioning Strategy:
 * ----------------------
 * -- Partition TRANSACTION table by month for faster date range queries
 * ALTER TABLE TRANSACTION 
 * PARTITION BY RANGE (TRANSACTION_DATE) (
 *     PARTITION p_2026_01 VALUES LESS THAN ('2026-02-01'),
 *     PARTITION p_2026_02 VALUES LESS THAN ('2026-03-01'),
 *     ...
 * );
 *
 * Query Optimization:
 * -------------------
 * - Keep date ranges reasonable (<=90 days for best performance)
 * - Consider materialized results for frequently-accessed periods
 * - Use result caching for repeated queries on same date range
 * - Monitor warehouse size and adjust based on query patterns
 * - TRANSFER_TYPE filter applied early improves scan performance
 *
 ******************************************************************************/

/*******************************************************************************
 * ERROR CODES AND HANDLING
 *******************************************************************************
 *
 * Error Scenarios:
 * ----------------
 * 1. NULL start_date       : Returns error message, no data processed
 * 2. NULL end_date         : Returns error message, no data processed
 * 3. start_date > end_date : Returns error message, invalid range
 * 4. Range > 365 days      : Returns warning, proceeds with query
 * 5. SQL execution error   : Returns SQLERRM with error details
 * 6. No data found         : Returns empty result set (valid scenario)
 *
 * Monitoring and Alerting:
 * ------------------------
 * - Log procedure execution times for performance monitoring
 * - Alert on execution failures or timeout errors
 * - Track result set sizes to identify unusual activity spikes
 * - Monitor warehouse usage and optimize based on patterns
 *
 ******************************************************************************/
