{% macro get_place_of_service_type(pos) -%}
    CASE
        WHEN UPPER(SUBSTR({{ pos }}, 1, 1)) = 'H' THEN 'Hospital'
        WHEN UPPER(SUBSTR({{ pos }}, 1, 1)) IN ('C', 'A') THEN 'Ambulatory'
        WHEN UPPER(SUBSTR({{ pos }}, 1, 1)) IN ('R', 'P', 'X') THEN 'Retail'
        ELSE 'Unknown'
    END
{%- endmacro %}
