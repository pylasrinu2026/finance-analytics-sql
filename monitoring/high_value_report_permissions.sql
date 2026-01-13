/*******************************************************************************
 * HIGH-VALUE TRANSACTION REPORT - ACCESS CONTROL & PERMISSIONS
 *******************************************************************************
 * Purpose: Define database permissions for compliance and risk monitoring roles
 *          to access high-value transaction reporting objects
 * 
 * Security Model:
 *   - Principle of least privilege (read-only access to reports)
 *   - Role-based access control (RBAC) for segregation of duties
 *   - Separate roles for compliance, risk, and executive access levels
 * 
 * Objects Secured:
 *   - vw_high_value_transactions_report (VIEW)
 *   - sp_generate_high_value_report (STORED PROCEDURE)
 * 
 * Created: 2026-01-12
 * Target Framework: SQL (Snowflake/PostgreSQL compatible with syntax adjustments)
 *******************************************************************************
 *
 * ROLE DEFINITIONS AND ACCESS LEVELS:
 * ------------------------------------
 * 
 * compliance_analyst_role:
 *   - Read access to high-value transaction views
 *   - Execute permissions for report generation procedures
 *   - Primary users: AML compliance team, regulatory reporting staff
 *   - Use case: Daily monitoring, regulatory report generation
 * 
 * risk_monitoring_role:
 *   - Read access to high-value transaction views
 *   - Execute permissions for report generation procedures
 *   - Primary users: Risk management team, fraud detection analysts
 *   - Use case: Risk assessment, fraud investigation
 * 
 * executive_reporting_role:
 *   - Read-only access to high-value transaction views
 *   - No execute permissions (uses pre-generated reports)
 *   - Primary users: Executive leadership, board reporting
 *   - Use case: High-level dashboards, strategic oversight
 * 
 * data_governance_role:
 *   - Read access to views for audit purposes
 *   - Monitor usage patterns and data quality
 *   - Primary users: Data governance team, audit staff
 *   - Use case: Audit trails, data quality monitoring
 *
 ******************************************************************************/

/*******************************************************************************
 * STEP 1: CREATE ROLES (IF THEY DON'T EXIST)
 * - Defines organizational roles for access control
 * - Roles can be assigned to individual users or groups
 ******************************************************************************/

-- Compliance analyst role for AML and regulatory reporting
CREATE ROLE IF NOT EXISTS compliance_analyst_role
    COMMENT = 'Role for compliance analysts monitoring high-value transactions for AML/regulatory purposes';

-- Risk monitoring role for fraud detection and risk assessment
CREATE ROLE IF NOT EXISTS risk_monitoring_role
    COMMENT = 'Role for risk management team monitoring customer transaction patterns';

-- Executive reporting role for leadership dashboards
CREATE ROLE IF NOT EXISTS executive_reporting_role
    COMMENT = 'Role for executive access to high-level transaction reporting (read-only)';

-- Data governance role for audit and data quality monitoring
CREATE ROLE IF NOT EXISTS data_governance_role
    COMMENT = 'Role for data governance team to monitor report usage and data quality';

/*******************************************************************************
 * STEP 2: GRANT SELECT PERMISSIONS ON VIEW
 * - Allows roles to query the high-value transaction report view
 * - Read-only access ensures data integrity
 ******************************************************************************/

-- Grant view access to compliance analysts
GRANT SELECT ON vw_high_value_transactions_report 
    TO ROLE compliance_analyst_role;

-- Grant view access to risk monitoring team
GRANT SELECT ON vw_high_value_transactions_report 
    TO ROLE risk_monitoring_role;

-- Grant view access to executive reporting (dashboard consumption)
GRANT SELECT ON vw_high_value_transactions_report 
    TO ROLE executive_reporting_role;

-- Grant view access to data governance for audit purposes
GRANT SELECT ON vw_high_value_transactions_report 
    TO ROLE data_governance_role;

/*******************************************************************************
 * STEP 3: GRANT EXECUTE PERMISSIONS ON STORED PROCEDURE
 * - Allows roles to execute the report generation procedure with date parameters
 * - Limited to operational roles (compliance and risk) for ad-hoc reporting
 ******************************************************************************/

-- Grant execute permission to compliance analysts for flexible date-range reports
GRANT EXECUTE ON PROCEDURE sp_generate_high_value_report(DATE, DATE)
    TO ROLE compliance_analyst_role;

-- Grant execute permission to risk monitoring team for investigation support
GRANT EXECUTE ON PROCEDURE sp_generate_high_value_report(DATE, DATE)
    TO ROLE risk_monitoring_role;

-- Grant execute permission to data governance for audit and testing
GRANT EXECUTE ON PROCEDURE sp_generate_high_value_report(DATE, DATE)
    TO ROLE data_governance_role;

-- NOTE: Executive role does NOT get execute permissions (uses pre-generated views only)

/*******************************************************************************
 * STEP 4: GRANT ACCESS TO UNDERLYING TABLES (IF REQUIRED)
 * - Optional: Grant read access to base tables for deep-dive analysis
 * - Recommendation: Limit to specific roles based on need-to-know
 ******************************************************************************/

-- Grant read access to TRANSACTION table for compliance analysts (investigative queries)
GRANT SELECT ON TRANSACTION 
    TO ROLE compliance_analyst_role;

-- Grant read access to ACCOUNT table for account-level analysis
GRANT SELECT ON ACCOUNT 
    TO ROLE compliance_analyst_role;

-- Grant read access to CUSTOMER table for customer profile analysis
GRANT SELECT ON CUSTOMER 
    TO ROLE compliance_analyst_role;

-- Grant read access to risk monitoring role for investigation support
GRANT SELECT ON TRANSACTION 
    TO ROLE risk_monitoring_role;

GRANT SELECT ON ACCOUNT 
    TO ROLE risk_monitoring_role;

GRANT SELECT ON CUSTOMER 
    TO ROLE risk_monitoring_role;

-- Data governance gets read access for audit purposes
GRANT SELECT ON TRANSACTION 
    TO ROLE data_governance_role;

GRANT SELECT ON ACCOUNT 
    TO ROLE data_governance_role;

GRANT SELECT ON CUSTOMER 
    TO ROLE data_governance_role;

-- NOTE: Executive role does NOT get direct table access (view-only for security)

/*******************************************************************************
 * STEP 5: GRANT WAREHOUSE USAGE (FOR QUERY EXECUTION)
 * - Allows roles to use compute warehouses for query execution
 * - Recommendation: Use dedicated compliance warehouse for cost tracking
 ******************************************************************************/

-- Create dedicated warehouse for compliance queries (optional)
-- CREATE WAREHOUSE IF NOT EXISTS COMPLIANCE_WH
--     WITH WAREHOUSE_SIZE = 'MEDIUM'
--     AUTO_SUSPEND = 60
--     AUTO_RESUME = TRUE
--     COMMENT = 'Dedicated warehouse for compliance and risk monitoring queries';

-- Grant warehouse usage to compliance role
GRANT USAGE ON WAREHOUSE COMPLIANCE_WH 
    TO ROLE compliance_analyst_role;

-- Grant warehouse usage to risk monitoring role
GRANT USAGE ON WAREHOUSE COMPLIANCE_WH 
    TO ROLE risk_monitoring_role;

-- Grant warehouse usage to executive reporting (lightweight queries only)
GRANT USAGE ON WAREHOUSE REPORTING_WH 
    TO ROLE executive_reporting_role;

-- Grant warehouse usage to data governance
GRANT USAGE ON WAREHOUSE COMPLIANCE_WH 
    TO ROLE data_governance_role;

/*******************************************************************************
 * STEP 6: ASSIGN ROLES TO USERS (EXAMPLE)
 * - Map individual users or groups to appropriate roles
 * - Use organizational identity management for production
 ******************************************************************************/

-- Example: Assign compliance analyst role to specific users
-- GRANT ROLE compliance_analyst_role TO USER john.doe@company.com;
-- GRANT ROLE compliance_analyst_role TO USER jane.smith@company.com;

-- Example: Assign risk monitoring role to risk team users
-- GRANT ROLE risk_monitoring_role TO USER risk.analyst@company.com;

-- Example: Assign executive reporting role to leadership
-- GRANT ROLE executive_reporting_role TO USER cfo@company.com;
-- GRANT ROLE executive_reporting_role TO USER cro@company.com;

-- Example: Assign data governance role to audit team
-- GRANT ROLE data_governance_role TO USER audit.team@company.com;

/*******************************************************************************
 * STEP 7: ROW-LEVEL SECURITY (OPTIONAL - ADVANCED)
 * - Implement row-level security policies for data isolation by country/region
 * - Use case: Multi-regional compliance with data sovereignty requirements
 ******************************************************************************/

-- Example: Create row access policy for country-based data isolation
-- CREATE ROW ACCESS POLICY country_isolation_policy AS (country STRING) RETURNS BOOLEAN ->
--     CASE
--         WHEN CURRENT_ROLE() = 'compliance_analyst_role_us' THEN country IN ('USA', 'CANADA')
--         WHEN CURRENT_ROLE() = 'compliance_analyst_role_eu' THEN country IN ('UK', 'GERMANY', 'FRANCE')
--         WHEN CURRENT_ROLE() = 'executive_reporting_role' THEN TRUE  -- Full access for executives
--         ELSE FALSE
--     END;

-- Apply policy to view (Snowflake syntax)
-- ALTER VIEW vw_high_value_transactions_report
--     ADD ROW ACCESS POLICY country_isolation_policy ON (country);

/*******************************************************************************
 * STEP 8: AUDIT AND MONITORING
 * - Enable query logging for security and compliance audit trails
 * - Monitor access patterns for unusual activity
 ******************************************************************************/

-- Enable query logging (Snowflake - automatic with ACCOUNT_USAGE schema)
-- Monitor via SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY view

-- Example audit query: Track who accessed high-value transaction reports
-- SELECT
--     USER_NAME,
--     ROLE_NAME,
--     QUERY_TEXT,
--     START_TIME,
--     END_TIME,
--     TOTAL_ELAPSED_TIME
-- FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
-- WHERE QUERY_TEXT ILIKE '%vw_high_value_transactions_report%'
--     AND START_TIME >= CURRENT_DATE - 30
-- ORDER BY START_TIME DESC;

/*******************************************************************************
 * VERIFICATION QUERIES
 * - Use these queries to verify permissions are correctly configured
 ******************************************************************************/

-- Verify role permissions on view
-- SHOW GRANTS ON VIEW vw_high_value_transactions_report;

-- Verify role permissions on procedure
-- SHOW GRANTS ON PROCEDURE sp_generate_high_value_report(DATE, DATE);

-- Verify user role assignments
-- SHOW GRANTS TO ROLE compliance_analyst_role;
-- SHOW GRANTS TO ROLE risk_monitoring_role;
-- SHOW GRANTS TO ROLE executive_reporting_role;
-- SHOW GRANTS TO ROLE data_governance_role;

-- Test access as specific role
-- USE ROLE compliance_analyst_role;
-- SELECT COUNT(*) FROM vw_high_value_transactions_report;
-- CALL sp_generate_high_value_report(CURRENT_DATE - 30, CURRENT_DATE);

/*******************************************************************************
 * REVOCATION PROCEDURES (FOR REFERENCE)
 * - Use these commands to revoke access when users change roles or leave
 ******************************************************************************/

-- Revoke view access from a role
-- REVOKE SELECT ON vw_high_value_transactions_report FROM ROLE compliance_analyst_role;

-- Revoke procedure execution from a role
-- REVOKE EXECUTE ON PROCEDURE sp_generate_high_value_report(DATE, DATE) FROM ROLE risk_monitoring_role;

-- Revoke role from a user
-- REVOKE ROLE compliance_analyst_role FROM USER john.doe@company.com;

-- Drop role (if no longer needed - use with caution)
-- DROP ROLE IF EXISTS deprecated_role_name;

/*******************************************************************************
 * COMPLIANCE NOTES
 *******************************************************************************
 *
 * Regulatory Requirements:
 * ------------------------
 * - SOX Compliance: Segregation of duties via role-based access
 * - GDPR/Privacy: Row-level security for data sovereignty
 * - PCI-DSS: Restricted access to financial transaction data
 * - AML/KYC: Audit trails for all high-value transaction queries
 * 
 * Best Practices:
 * ---------------
 * - Review role assignments quarterly
 * - Implement least privilege principle
 * - Enable MFA for all privileged roles
 * - Monitor and alert on unusual access patterns
 * - Document all permission changes in change management system
 * - Use service accounts for automated reporting processes
 * - Rotate credentials regularly per security policy
 * 
 * Audit Trail Requirements:
 * -------------------------
 * - Log all SELECT queries on high-value transaction reports
 * - Track procedure executions with parameter values
 * - Retain audit logs for minimum 7 years (regulatory requirement)
 * - Generate monthly access reports for security review
 * - Alert on after-hours access by non-authorized users
 *
 ******************************************************************************/

/*******************************************************************************
 * INTEGRATION WITH IDENTITY MANAGEMENT
 *******************************************************************************
 *
 * Recommended Approach:
 * ---------------------
 * 1. Integrate with corporate SSO (SAML 2.0 / OAuth)
 * 2. Sync roles from Active Directory / Okta / Azure AD
 * 3. Implement automated provisioning/de-provisioning
 * 4. Use groups for role assignment instead of individual users
 * 5. Enable conditional access policies (IP restrictions, device compliance)
 * 
 * Example: Snowflake integration with Okta
 * -----------------------------------------
 * -- Create security integration
 * CREATE SECURITY INTEGRATION okta_integration
 *     TYPE = SAML2
 *     ENABLED = TRUE
 *     SAML2_ISSUER = 'https://company.okta.com'
 *     SAML2_SSO_URL = 'https://company.okta.com/app/snowflake/sso/saml'
 *     SAML2_PROVIDER = 'OKTA'
 *     SAML2_X509_CERT = '<certificate_content>';
 * 
 * -- Map Okta groups to Snowflake roles
 * ALTER SECURITY INTEGRATION okta_integration 
 *     SET SAML2_SNOWFLAKE_ISSUER_URL = 'https://company.snowflakecomputing.com';
 *
 ******************************************************************************/
