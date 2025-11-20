/******************************************************************************
 * SETUP MOCK DATA
 ******************************************************************************/

-- 1. SET UP ROLES AND WAREHOUSE
USE ROLE SYSADMIN; 
CREATE OR REPLACE WAREHOUSE CIVIE_CORTEX_WH WITH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;
USE WAREHOUSE CIVIE_CORTEX_WH;

-- 2. CREATE DATABASE AND SCHEMAS
CREATE DATABASE IF NOT EXISTS CIVIE_CORTEX_DEMO;
CREATE SCHEMA IF NOT EXISTS CIVIE_CORTEX_DEMO.RAW_DATA; -- Schema for source data
CREATE SCHEMA IF NOT EXISTS CIVIE_CORTEX_DEMO.DBT_PROJECT; -- Schema for Git Repo and Cortex objects
USE SCHEMA CIVIE_CORTEX_DEMO.RAW_DATA;

-- 3. MOCK DATA: PATIENTS TABLE
CREATE OR REPLACE TABLE PATIENTS (
    PATIENT_ID VARCHAR,
    DATE_OF_BIRTH DATE,
    INSURANCE_PLAN VARCHAR,
    PCP_ID VARCHAR
);

INSERT INTO PATIENTS (PATIENT_ID, DATE_OF_BIRTH, INSURANCE_PLAN, PCP_ID) VALUES
('P-1001', '1955-03-15', 'MEDICARE ADVANTAGE', 'DR-1'), -- High Risk: Age & Medicare
('P-1002', '1998-11-20', 'BLUE CROSS', 'DR-2'),
('P-1003', '1938-01-01', 'CASH PAY', 'DR-3'), -- High Risk: Age only
('P-1004', '2010-07-25', 'MEDICAID', 'DR-4');

-- 4. MOCK DATA: ENCOUNTERS TABLE
CREATE OR REPLACE TABLE ENCOUNTERS (
    ENCOUNTER_ID VARCHAR,
    PATIENT_ID VARCHAR,
    ENCOUNTER_DATE DATE,
    PROVIDER_ID VARCHAR,
    PRIMARY_DX_CODE VARCHAR -- Diagnosis Code (ICD-10)
);

INSERT INTO ENCOUNTERS (ENCOUNTER_ID, PATIENT_ID, ENCOUNTER_DATE, PROVIDER_ID, PRIMARY_DX_CODE) VALUES
('E-001', 'P-1001', '2025-01-10', 'DR-1', 'I50'), -- Cardio/Respiratory
('E-002', 'P-1002', '2025-01-15', 'DR-2', 'V80'), -- Preventive
('E-003', 'P-1001', '2025-03-01', 'DR-1', 'J45'), -- Cardio/Respiratory (second encounter)
('E-004', 'P-1004', '2025-04-05', 'DR-4', 'E88'), -- Injury/Trauma
('E-005', 'P-1003', '2025-05-20', 'DR-3', 'A01'); -- Other


/******************************************************************************
 * SETUP GIT REPOSITORY STAGE
 ******************************************************************************/

 -- Use a secure schema to house sensitive information
USE SCHEMA CIVIE_CORTEX_DEMO.DBT_PROJECT; 

-- -- NOTE: This step is typically run by a role with CREATE SECRET privilege.
--          For demo purposes, we're using a public git repository and don't need secrets.
--
-- CREATE OR REPLACE SECRET civie_git_secret
--     TYPE = password
--     -- The USERNAME is often your Git username, but for BitBucket it might be 'x-token-auth'.
--     USERNAME = '<YOUR_GIT_USERNAME>'
--     -- The PASSWORD is your Personal Access Token (PAT)
--     PASSWORD = '<YOUR_PERSONAL_ACCESS_TOKEN>'
--     COMMENT = 'Secret for authenticating with the dbt project Git repository.';

-- Must be run by ACCOUNTADMIN or a role with CREATE INTEGRATION privilege
USE ROLE ACCOUNTADMIN; 

CREATE OR REPLACE API INTEGRATION civie_git_api_integration
    API_PROVIDER = git_https_api
    -- IMPORTANT: Restrict this to your organization/repository URL for security.
    API_ALLOWED_PREFIXES = ('https://github.com/paulboal/') -- e.g., 'https://github.com/Snowflake-Labs/'
    -- Allow the integration to use the secret we created in step 1
    -- ALLOWED_AUTHENTICATION_SECRETS = (CIVIE_CORTEX_DEMO.DBT_PROJECT.civie_git_secret)
    ENABLED = TRUE
    COMMENT = 'API Integration for CIVIE dbt project Git connection.';

-- Switch back to a development/admin role
USE ROLE SYSADMIN; 
USE SCHEMA CIVIE_CORTEX_DEMO.DBT_PROJECT; 

-- 3. Create the GIT REPOSITORY Clone
CREATE OR REPLACE GIT REPOSITORY civie_dbt_repo
    ORIGIN = 'https://github.com/paulboal/dbt_chat.git' -- The full HTTPS URL of your dbt repo
    API_INTEGRATION = civie_git_api_integration
    -- GIT_CREDENTIALS = civie_git_secret -- The Secret containing the PAT
    COMMENT = 'Local clone of the CIVIE dbt project for Cortex indexing.';

-- 4. Initial Fetch (Sync)
-- This command pulls the current state of the code into the Snowflake Git Repository Stage.
ALTER GIT REPOSITORY civie_dbt_repo FETCH;

-- 5. Verify the files are accessible (The stage location will be automatic)
LS @civie_dbt_repo/branches/main/;

/*****************************************************************************
 * SETUP DBT FILE INDEXING
 *****************************************************************************/

 USE SCHEMA CIVIE_CORTEX_DEMO.DBT_PROJECT;

-- 1. CREATE FILE FORMAT FOR READING TEXT
CREATE OR REPLACE FILE FORMAT TEXT_FILE_FORMAT
  TYPE = 'CUSTOM';

-- 2. CREATE FILE INDEXING TABLE
-- This table will store the content of all your dbt files for indexing
CREATE OR REPLACE TABLE dbt_file_index (
    FILE_PATH VARCHAR,
    REPO_PATH VARCHAR,
    FILE_CONTENT VARCHAR
);

-- 3. LOAD FILE CONTENTS FROM GIT REPOSITORY STAGE (CORRECTED COMMAND)
-- **CRITICAL STEP**: Use INSERT INTO ... SELECT FROM @STAGE instead of COPY INTO.
INSERT INTO dbt_file_index (FILE_PATH, REPO_PATH, FILE_CONTENT)
SELECT 
    METADATA$FILENAME AS FILE_PATH,
    SPLIT_PART(METADATA$FILENAME, '/dbt/', 2) AS REPO_PATH,
    $1 AS FILE_CONTENT -- $1 contains the entire file content due to the file format settings
FROM @civie_dbt_repo/branches/main/ -- Replace with your actual Git Repository Stage
(file_format => 'TEXT_FILE_FORMAT')
WHERE 
    FILE_PATH ILIKE '%dbt/%.sql'
    OR FILE_PATH ILIKE '%dbt/%.yml'
    OR FILE_PATH ILIKE '%dbt/%.md';

SELECT COUNT(*) FROM dbt_file_index; -- Verify files were loaded (should be 7)

SELECT * FROM dbt_file_index LIMIT 5; -- Preview some loaded files


/*
 * SETUP CORTEX RAG AGENT
 */


-- 1. GRANT CORTEX ACCESS (If not done already)
-- Note: This is usually granted to a custom role, not SYSADMIN directly
-- GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE your_analyst_role;

-- 2. CREATE CORTEX SEARCH SERVICE (The RAG Index)
-- This service vectorizes the FILE_CONTENT column
CREATE OR REPLACE CORTEX SEARCH SERVICE civie_dbt_rag_service
ON FILE_CONTENT -- The column to vectorize and search on
ATTRIBUTES FILE_PATH, REPO_PATH -- The file path to return as context
WAREHOUSE = CIVIE_CORTEX_WH
TARGET_LAG = '1 minute' -- Automatically update if files change
AS
SELECT 
    FILE_PATH, -- potentially reformat this to be a link directly to GitHub
    REPO_PATH,
    FILE_CONTENT 
FROM dbt_file_index;

-- Wait for the service to become active (usually a few minutes)
SELECT * FROM CIVIE_CORTEX_DEMO.INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES;


-- 3. CREATE CORTEX RAG AGENT
-- This agent uses the search service to answer questions about the dbt project

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE AGENT snowflake_intelligence.agents.civie_dbt_rag_agent
  COMMENT = 'You spend all this time creating dbt models with great documentation and test cases. Everything anyone would ever need to know about how data is being interpreted and metrics are being calculated is somewhere in these dbt model files... but who has time to go digging around to find the rules and answer business user questions like "how is encounter type determined?" or "which source fields are used in which order to set patient birth date?"  This agent has the answers!'
  PROFILE = '{"display_name": "CIVIE dbt RAG Agent", "avatar":  "business-icon.png", "color": "red"}'
  FROM SPECIFICATION
  $$
  orchestration:
    budget:
      seconds: 30
      tokens: 16000

  instructions:

    response: "### 3. Response Formatting
* Start the response with a concise, direct answer.
* Break down complex explanations using **bold text** and bullet points for readability.
* **Cite the source files** that were used to generate the answer. The search tool will provide the `FILE_PATH`; include this path in your response (e.g., Source: `models/marts/dim_patients.sql`).
"

    orchestration: "You are the CIVIE dbt Code Analyst, an expert in understanding dbt project code and healthcare data analytics.
Your primary function is to answer developer and analyst questions about the dbt project structure, business logic, documentation, and SQL code.

### 1. Tool Use and Retrieval Strategy
* **ALWAYS** use the dbtprojectfiles tool for any question regarding code content, business logic, column definitions, file paths, or project definitions.
* **NEVER** guess or invent information. If the required information is not found using the search tool, state clearly that you do not have sufficient context from the project files.

### 2. Interpretation and Analysis
* **Interpret questions semantically:** The user is asking about the code. When answering a logic question (e.g., `How is is_high_risk_patient defined?`), you must synthesize information from the `.yml` documentation AND the corresponding `.sql` file to provide a complete answer.
* **If providing SQL code:** Format the SQL clearly within a code block.
* **If explaining a macro:** Explain the Jinja logic in plain English first, then provide the code block for context.
"

    system: "You are a friendly agent that helps with business questions"

    sample_questions:
      - question: "How is diagnosis code determined?"
      - question: "Which patients get flagged as `high risk`?"

  tools:
    - tool_spec:
        type: "cortex_search"
        name: "dbtProjectFiles"
        description: "This contains all the content from our dbt projects."

  tool_resources:
    dbtProjectFiles:
      name: "civie_cortex_demo.dbt_project.civie_dbt_rag_service"
      max_results: "10"
      title_column: "REPO_PATH"
      id_column: "FILE_PATH"
  $$;



  
/* We also need a way to keep the index table up to date as the Git repository changes.
    The following stored procedure can be scheduled to run periodically (e.g., hourly)
    to refresh the dbt_file_index table with any new or modified files from the Git repo.
*/

/*
USE SCHEMA CIVIE_CORTEX_DEMO.DBT_PROJECT;
USE WAREHOUSE CORTEX_WH;

-- Create a procedure to refresh the index table
CREATE OR REPLACE PROCEDURE refresh_dbt_index()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- 1. Create a temporary table to hold the file paths and last modified times 
    --    of ALL files in the Git Repository Stage.
    CREATE OR REPLACE TEMPORARY TABLE changed_files AS
    SELECT
        RELATIVE_PATH AS FILE_PATH,
        LAST_MODIFIED AS LAST_MODIFIED_TIME
    FROM @civie_dbt_repo/branches/main/ -- **YOUR REPO STAGE PATH**
    (
        DIRECTORY => @civie_dbt_repo/branches/main/,
        PATTERN => '.*(\.sql|\.yml|\.md)$' -- Filter only for dbt content files
    );

    -- 2. Use a MERGE statement to efficiently update or insert only the files that
    --    are new OR have been modified in the last 61 minutes (to catch the hourly refresh).
    MERGE INTO dbt_file_index AS target
    USING (
        SELECT 
            t1.FILE_PATH, 
            t1.LAST_MODIFIED_TIME,
            t2.$1 AS NEW_CONTENT
        FROM changed_files t1
        -- Join to the stage again to get the content of the file
        INNER JOIN @civie_dbt_repo/branches/main/ t2 ON t1.FILE_PATH = METADATA$FILENAME
        (FILE_FORMAT => 'TEXT_FILE_FORMAT')
        WHERE t1.LAST_MODIFIED_TIME >= DATEADD(minute, -61, CURRENT_TIMESTAMP())
        -- Include files that are new (not in target)
        OR NOT EXISTS (SELECT 1 FROM dbt_file_index WHERE dbt_file_index.FILE_PATH = t1.FILE_PATH)
    ) AS source
    ON target.FILE_PATH = source.FILE_PATH
    WHEN MATCHED AND target.FILE_CONTENT <> source.NEW_CONTENT THEN
        -- If the file content has changed, update the content
        UPDATE SET target.FILE_CONTENT = source.NEW_CONTENT
    WHEN NOT MATCHED THEN
        -- If the file is new, insert it
        INSERT (FILE_PATH, FILE_CONTENT) VALUES (source.FILE_PATH, source.NEW_CONTENT);

    RETURN 'DBT file index refresh process completed successfully.';
END;
$$;

*/