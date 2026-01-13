/*******************************************************************************
 * TRANSACTION TRANSFER_TYPE INDEX
 *******************************************************************************
 * Purpose: Create index on TRANSFER_TYPE column to optimize revenue queries
 *          that filter out INTERNAL transfers
 * 
 * Created: 2026-01-12
 * Modified: 2026-01-12 - Initial creation for INTERNAL transfer filtering
 * 
 * Business Impact:
 *   - Improves performance of revenue calculation queries
 *   - Reduces table scan time for high-volume transaction tables
 *   - Essential for queries filtering by TRANSFER_TYPE
 * 
 * Target Framework: SQL (Compatible with PostgreSQL, MySQL, Snowflake, SQL Server)
 ******************************************************************************/

-- Standard B-tree index on TRANSFER_TYPE column
-- This index supports queries with WHERE TRANSFER_TYPE = 'value' or WHERE TRANSFER_TYPE <> 'value'
CREATE INDEX IF NOT EXISTS idx_transaction_transfer_type
    ON TRANSACTION(TRANSFER_TYPE);

/*******************************************************************************
 * ALTERNATIVE INDEXING STRATEGIES
 ******************************************************************************/

-- Option 1: Partial Index (PostgreSQL, supports NULL filtering efficiently)
-- Only indexes rows where TRANSFER_TYPE is not NULL
-- Reduces index size and improves performance for non-NULL queries
/*
CREATE INDEX IF NOT EXISTS idx_transaction_transfer_type_notnull
    ON TRANSACTION(TRANSFER_TYPE)
    WHERE TRANSFER_TYPE IS NOT NULL;
*/

-- Option 2: Filtered Index (SQL Server syntax)
-- Similar to partial index, optimized for specific conditions
/*
CREATE INDEX idx_transaction_transfer_type_notnull
    ON TRANSACTION(TRANSFER_TYPE)
    WHERE TRANSFER_TYPE IS NOT NULL;
*/

-- Option 3: Composite Index with Date (for date-range revenue queries)
-- Combines TRANSFER_TYPE with TRANSACTION_DATE for optimal performance
-- Use this if most queries filter by both columns
/*
CREATE INDEX IF NOT EXISTS idx_transaction_transfer_type_date
    ON TRANSACTION(TRANSFER_TYPE, TRANSACTION_DATE);
*/

-- Option 4: Covering Index (includes frequently accessed columns)
-- Reduces need to access main table for SELECT queries
-- Larger index, but can significantly improve query performance
/*
CREATE INDEX IF NOT EXISTS idx_transaction_transfer_type_covering
    ON TRANSACTION(TRANSFER_TYPE, TRANSACTION_DATE, AMOUNT, ACCOUNT_ID)
    WHERE TRANSFER_TYPE IS NOT NULL;
*/

/*******************************************************************************
 * INDEX MAINTENANCE RECOMMENDATIONS
 *******************************************************************************
 * 
 * Reindex Frequency:
 * - PostgreSQL: REINDEX INDEX idx_transaction_transfer_type; (weekly/monthly)
 * - MySQL: OPTIMIZE TABLE TRANSACTION; (monthly)
 * - SQL Server: ALTER INDEX idx_transaction_transfer_type ON TRANSACTION REBUILD;
 * - Snowflake: Automatic maintenance, no manual intervention required
 * 
 * Monitoring:
 * - Track index usage statistics to ensure index is being utilized
 * - Monitor index size growth relative to table size
 * - Analyze query execution plans to verify index effectiveness
 * 
 * Performance Testing:
 * - Before index: Run EXPLAIN/EXPLAIN ANALYZE on revenue queries
 * - After index: Compare execution plans and runtime
 * - Expected improvement: 50-90% reduction in query time for large tables
 * 
 ******************************************************************************/

/*******************************************************************************
 * VERIFY INDEX USAGE (Query Examples)
 ******************************************************************************/

-- PostgreSQL: Check if index is being used
/*
EXPLAIN ANALYZE
SELECT SUM(AMOUNT) 
FROM TRANSACTION 
WHERE TRANSFER_TYPE <> 'INTERNAL' OR TRANSFER_TYPE IS NULL;
*/

-- SQL Server: Check index usage statistics
/*
SELECT 
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE OBJECT_NAME(s.object_id) = 'TRANSACTION'
    AND i.name = 'idx_transaction_transfer_type';
*/

-- MySQL: Check index cardinality and usage
/*
SHOW INDEX FROM TRANSACTION WHERE Key_name = 'idx_transaction_transfer_type';
*/
