Change Request 1 (New Business Rule)

User asks AI:

“We want to exclude INTERNAL transfers from all revenue calculations.
Update the SQL and explain what you changed.”

AI should:
Identify TRANSACTION_TYPE or CHANNEL

Modify:
monthly_customer_summary.sql
revenue_report.sql

Explain:
Which files changed
Why the logic changed
Business impact

🔹 Change Request 2 (New Feature)
User asks AI:
“Add a new report for high-value transactions above 1,000,000 per day per customer.”

AI should:
Create:
transformations/high_value_transactions.sql

Join CUSTOMER → ACCOUNT → TRANSACTION
Explain new table & logic
