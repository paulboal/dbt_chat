/*
* 05_maintenance.sql
* This script sets up maintenance tasks and procedures for keeping the dbt file index up to date
 */

USE SCHEMA DEMO_CORTEX_DEMO.DBT_PROJECT;
USE WAREHOUSE DEMO_CORTEX_WH;

-- 1. Create a procedure to refresh the index table
CREATE OR REPLACE PROCEDURE refresh_dbt_index()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- 1. Refresh the dbt repo to get the latest files
    ALTER GIT REPOSITORY demo_dbt_repo FETCH;

    -- 1. Create a temporary table to hold the file paths and last modified times 
    --    of ALL files in the Git Repository Stage.
    CREATE OR REPLACE TEMPORARY TABLE changed_files AS
    SELECT 
        METADATA$FILENAME AS FILENAME,
        METADATA$FILE_LAST_MODIFIED AS FILE_LAST_MODIFIED
    FROM @demo_dbt_repo/branches/main/
    (file_format => 'TEXT_FILE_FORMAT')
    WHERE 
        FILENAME ILIKE '%dbt/%.sql'
        OR FILENAME ILIKE '%dbt/%.yml'
        OR FILENAME ILIKE '%dbt/%.md';

    -- 2. Use a MERGE statement to efficiently update or insert only the files that
    --    are new OR have been modified in the last 61 minutes (to catch the hourly refresh).
    MERGE INTO dbt_file_index AS target
    USING (
        SELECT 
            t1.FILENAME, 
            t2.METADATA$FILENAME,
            t1.FILE_LAST_MODIFIED,
            SPLIT_PART(t1.FILENAME, '/dbt/', 2) AS REPO_PATH,
            t2.$1 as NEW_CONTENT,
        FROM changed_files t1
        -- Join to the stage again to get the content of the file
        JOIN @demo_dbt_repo/branches/main/ 
            (FILE_FORMAT => 'TEXT_FILE_FORMAT',
             PATTERN => 'dbt.*\.sql|dbt.*\.yml|dbt.*\.md'
            ) t2 ON t1.FILENAME = t2.METADATA$FILENAME
        
    ) AS source
    ON target.FILENAME = source.FILENAME
    WHEN MATCHED AND target.FILE_LAST_MODIFIED < source.FILE_LAST_MODIFIED THEN
        -- If the file content has changed, update the content
        UPDATE SET target.FILE_CONTENT = source.NEW_CONTENT
    WHEN NOT MATCHED THEN
        -- If the file is new, insert it
        INSERT (FILENAME, FILE_LAST_MODIFIED, REPO_PATH, FILE_CONTENT) 
        VALUES (source.FILENAME, source.FILE_LAST_MODIFIED, source.REPO_PATH, source.NEW_CONTENT);

    RETURN 'Git repository and DBT file index refresh process completed successfully.';
END;
$$;

-- 2. Create a task to run the refresh procedure at the top of every hour (UTC)
CREATE OR REPLACE TASK refresh_dbt_index_task
    WAREHOUSE = DEMO_CORTEX_WH
    SCHEDULE = 'USING CRON 0 * * * * UTC'
AS
    CALL refresh_dbt_index();

-- Enable the task
ALTER TASK refresh_dbt_index_task RESUME;


CALL refresh_dbt_index();
