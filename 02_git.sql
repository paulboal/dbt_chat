/*
 * 02_git.sql
 * This script sets up the Git repository integration for the dbt project.
 *
 * Assumptions to change in production:
 * - Add git secret
 * - Restrict API integration to your organization's Git URL
 * - Use a private repo with authentication
 * - Implement an network access policy if needed
 */

USE SCHEMA DEMO_CORTEX_DEMO.DBT_PROJECT; 

/**
-- 1. Create a Secret to store Git credentials (Personal Access Token)
-- NOTE: This step is typically run by a role with CREATE SECRET privilege.
--          For demo purposes, we're using a public git repository and don't need secrets.

CREATE OR REPLACE SECRET demo_git_secret
    TYPE = password
    -- The USERNAME is often your Git username, but for BitBucket it might be 'x-token-auth'.
    USERNAME = '<YOUR_GIT_USERNAME>'
    -- The PASSWORD is your Personal Access Token (PAT)
    PASSWORD = '<YOUR_PERSONAL_ACCESS_TOKEN>'
    COMMENT = 'Secret for authenticating with the dbt project Git repository.';
**/


-- 2. Create the API INTEGRATION for Git access

-- The accountadmin role is required to create API INTEGRATIONS
USE ROLE ACCOUNTADMIN; 

CREATE OR REPLACE API INTEGRATION demo_git_api_integration
    API_PROVIDER = git_https_api
    -- IMPORTANT: Restrict this to your organization/repository URL for security.
    API_ALLOWED_PREFIXES = ('https://github.com/paulboal/') -- e.g., 'https://github.com/Snowflake-Labs/'
    -- Allow the integration to use the secret we created in step 1
    -- ALLOWED_AUTHENTICATION_SECRETS = (demo_CORTEX_DEMO.DBT_PROJECT.demo_git_secret)
    ENABLED = TRUE
    COMMENT = 'API Integration for dbt project Git connection.';


-- 3. Create the GIT REPOSITORY Clone
-- Switch back to a development/admin role
USE ROLE SYSADMIN; 
USE SCHEMA demo_CORTEX_DEMO.DBT_PROJECT; 

CREATE OR REPLACE GIT REPOSITORY demo_dbt_repo
    ORIGIN = 'https://github.com/paulboal/dbt_chat.git' -- The full HTTPS URL of your dbt repo
    API_INTEGRATION = demo_git_api_integration
    -- GIT_CREDENTIALS = demo_git_secret -- The Secret containing the PAT
    COMMENT = 'Local clone of the dbt project for Cortex indexing.';

-- 4. Initial Fetch (Sync)
-- This command pulls the current state of the code into the Snowflake Git Repository Stage.
ALTER GIT REPOSITORY demo_dbt_repo FETCH;

-- 5. Verify the files are accessible (The stage location will be automatic)
LS @demo_dbt_repo/branches/main/;


