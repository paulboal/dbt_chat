
USE SCHEMA DEMO_CORTEX_DEMO.DBT_PROJECT;
USE WAREHOUSE DEMO_CORTEX_WH;


-- Our function to refresh the git repository and file index table
CALL refresh_dbt_index();

SELECT * FROM dbt_file_index;

