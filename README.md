# dbt Chat Demo

You've spent all this time creating dbt models with great documentation and test cases. Everything anyone would ever need to know about how data is being interpreted and metrics are being calculated is somewhere in these dbt model files... but who has time to go digging around to find the rules and answer business user questions like "how is encounter type determined?" or "which source fields are used in which order to set patient birth date?"

Snowflake Intelligence has the time to do all that!

## Demo Scenario

## Prerequisites

* Have a public github repository repository with a dbt project in it, similar to [this one](https://github.com/paulboal/dbt_demo)


## Setup
1. [Database and Schema skeleton](01_skeleton.sql)
2. [Git repo integration](02_git.sql) 
3. [Cortex Search service setup](03_cortex.sql)
4. [Cortex Agent](04_agent.sql)
5. [Maintenance Scripts](05_maintenance.sql)

