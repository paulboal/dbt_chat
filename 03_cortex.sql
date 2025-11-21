/*
 * 03_cortex.sql
 * This script setups up the Cortex Search index
 */

USE ROLE ACCOUNTADMIN;

USE SCHEMA DEMO_CORTEX_DEMO.DBT_PROJECT;

-- 1. CREATE FILE FORMAT FOR READING TEXT
CREATE OR REPLACE FILE FORMAT TEXT_FILE_FORMAT
  TYPE = 'CSV'
  RECORD_DELIMITER = '0x01'
  FIELD_DELIMITER = '0x02' -- Newline as delimiter to read entire file as single column
  SKIP_HEADER = 0;

-- 2. CREATE FILE INDEXING TABLE
-- This table will store the content of all your dbt files for indexing
CREATE OR REPLACE TABLE dbt_file_index (
    FILENAME VARCHAR,
    REPO_PATH VARCHAR,
    FILE_LAST_MODIFIED TIMESTAMP_NTZ,
    FILE_CONTENT VARCHAR
);

-- 3. LOAD FILE CONTENTS FROM GIT REPOSITORY STAGE (CORRECTED COMMAND)
-- **CRITICAL STEP**: Use INSERT INTO ... SELECT FROM @STAGE instead of COPY INTO.
INSERT INTO dbt_file_index (FILENAME, FILE_LAST_MODIFIED, REPO_PATH, FILE_CONTENT)
SELECT 
    METADATA$FILENAME AS FILENAME,
    METADATA$FILE_LAST_MODIFIED AS FILE_LAST_MODIFIED,
    SPLIT_PART(METADATA$FILENAME, '/dbt/', 2) AS REPO_PATH,
    $1 AS FILE_CONTENT -- $1 contains the entire file content due to the file format settings
FROM @demo_dbt_repo/branches/main/ -- Replace with your actual Git Repository Stage
(file_format => 'TEXT_FILE_FORMAT')
WHERE 
    FILENAME ILIKE '%dbt/%.sql'
    OR FILENAME ILIKE '%dbt/%.yml'
    OR FILENAME ILIKE '%dbt/%.md';


-- #. GRANT CORTEX ACCESS (If not done already)
-- Note: This is usually granted to a custom role, not SYSADMIN directly
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE your_analyst_role;

-- 4. CREATE CORTEX SEARCH SERVICE (The RAG Index)
-- This service vectorizes the FILE_CONTENT column
CREATE OR REPLACE CORTEX SEARCH SERVICE demo_dbt_rag_service
ON FILE_CONTENT -- The column to vectorize and search on
ATTRIBUTES FILENAME, REPO_PATH, FILE_LAST_MODIFIED -- The file path to return as context
WAREHOUSE = DEMO_CORTEX_WH
TARGET_LAG = '1 minute' -- Automatically update if files change
AS
SELECT 
    FILENAME, -- potentially reformat this to be a link directly to GitHub
    REPO_PATH,
    FILE_LAST_MODIFIED,
    FILE_CONTENT 
FROM dbt_file_index;

-- Wait for the service to become active (usually a few minutes)
SELECT * FROM DEMO_CORTEX_DEMO.INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES;
