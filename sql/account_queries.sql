-- Databricks notebook source
-- MAGIC %md
-- MAGIC ### Account Admin Permission Changes
-- MAGIC Databricks account admin users should be limited to few trusted personas responsible for managing your Databricks account. The granting of new admin privileges should be reviewed.

-- COMMAND ----------

SELECT
  timestamp,
  email,
  actionName,
  requestParams.targetUserName,
  sourceIpAddress
FROM
  audit_logs.gold_account_accounts
WHERE
  actionName IN ("setAccountAdmin", "removeAccountAdmin")
ORDER BY
  timestamp DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Repeated Failed Login Attempts
-- MAGIC Customers are encouraged to leverage their SSO capability and disable local password usage for all users except the account owner. In the event local passwords are still used, this detection helps monitor for any possible brute force attacks to login to the workspace. In the example below, it buckets repeated login attempts in a 30 minute window.

-- COMMAND ----------

SELECT
  WINDOW(timestamp, '30 minutes'),
  requestParams.user,
  statusCode,
  count(*) AS total
FROM
  audit_logs.gold_account_accounts
WHERE
  actionName = 'login'
  AND statusCode <> 200
GROUP BY
  1,
  2,
  3
ORDER BY WINDOW DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ###Detect changes to Production workspaces
-- MAGIC Databricks account administrators can [Create and manage workspaces using the account console](https://docs.databricks.com/administration-guide/account-settings-e2/workspaces.html). However, for specific resources (I.e. production workspaces) you may want to be proactively informed if they have been updated or deleted. 
-- MAGIC 
-- MAGIC The following query can be used to monitor changes to Databricks workspaces which have ```prod``` in their ```workspace_name```

-- COMMAND ----------

SELECT
  timestamp,
  email,
  actionName,
  requestParams.workspace_id AS workspace_id,
  requestParams,
  result:workspace.workspace_name AS workspace_name,
  result:workspace.aws_account_id AS aws_account_id
FROM
  audit_logs.gold_account_accountsmanager
WHERE
  actionName IN (
    "updateWorkspaceConfiguration",
    "deleteWorkspaceConfiguration"
  )
  AND contains(result:workspace.workspace_name, "prod")
ORDER BY
  timestamp DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We can extend the query above to search for all account objects associated with our production workspaces (assuming they share an established naming convention).
-- MAGIC 
-- MAGIC 
-- MAGIC The following query can be used to monitor changes to account objects which have ```prod``` in their name

-- COMMAND ----------

SELECT * FROM (SELECT
  timestamp,
  email,
  actionName,
  requestParams.workspace_id AS workspace_id,
  requestParams,
  map_filter(map(
  "workspace_name", result :workspace.workspace_name, 
  "network_name", result :network.network_name, 
  "storage_configuration_name", result :storage_configuration.storage_configuration_name,
  "credentials_name", result :credentials.credentials_name,
  "key_alias", result :customer_managed_key:aws_key_info.key_alias,
  "vpc_endpoint_name", result :vpc_endpoint.vpc_endpoint_name,
  "private_access_settings_name", result :private_access_settings.private_access_settings_name
  ), 
  (k, v) -> v IS NOT NULL ) AS resources,
  result
FROM
  audit_logs.gold_account_accountsmanager
WHERE
  actionName IN (
    "deleteCredentialsConfiguration",
    "deleteCustomerManagedKeyConfiguration",
    "deleteNetworkConfiguration",
    "deletePrivateAccessSettings",
    "deleteStorageConfiguration",
    "deleteVpcEndpoint"
    "deleteWorkspaceConfiguration"
    "updateCredentialsConfiguration",
    "updateCustomerManagedKeyConfiguration",
    "updateNetworkConfiguration",
    "updatePrivateAccessSettings",
    "updateStorageConfiguration",
    "updateVpcEndpoint"
    "updateWorkspaceConfiguration"
  )) 
  WHERE EXISTS(map_values(resources), x -> contains(x, "prod"))
ORDER BY
  timestamp DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ###Most Popular Data Assets
-- MAGIC [Unity Catalog](https://databricks.com/product/unity-catalog) makes it easy to discover, audit and govern data assets in one place. Having a unified governance layer allows us to perform analytics on our data products. So we can (for example) run a query to see what our most popular datasets are.

-- COMMAND ----------

SELECT
  CASE
    WHEN actionName = "getTable" THEN "uc_table"
    WHEN actionName = "getShare" THEN "delta_share"
    ELSE "other"
  END AS product_type,
  CASE
    WHEN actionName = "getTable" THEN requestParams.full_name_arg
    WHEN actionName = "getShare" THEN requestParams.name
    ELSE NULL
  END AS data_product,
  COUNT(*) AS total_requests
FROM
  audit_logs.gold_account_unitycatalog
WHERE date >= current_date() - 90
AND actionName IN ("getTable", "getShare")
AND email IS NOT NULL
GROUP BY
  1,
  2
ORDER BY
  total_requests DESC

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Which IP Addresses are being used to connect to my [Delta Shares](https://databricks.com/product/delta-sharing)?

-- COMMAND ----------

SELECT
  sourceIpAddress AS source_ip,
  statusCode AS status_code,
  count(*) AS total_requests
FROM
  audit_logs.gold_account_unitycatalog
WHERE
  date >= current_date() - 90
  AND actionName IN ("getShare")
GROUP BY
  1,
  2
ORDER BY
  total_requests DESC
