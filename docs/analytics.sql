-- Enable optional Terraform analytics, then select the generated Glue database.
SELECT kind, region, status, COUNT(*) AS evaluations
FROM policy_evaluations
GROUP BY kind, region, status
ORDER BY evaluations DESC;

SELECT operationid, explanation, retentiondays
FROM policy_evaluations
WHERE status = 'rejected'
LIMIT 100;
