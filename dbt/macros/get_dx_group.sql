{% macro get_dx_group(diagnosis_code) %}
    CASE
        WHEN LEFT({{ diagnosis_code }}, 1) IN ('J', 'I') THEN 'Cardio/Respiratory'
        WHEN LEFT({{ diagnosis_code }}, 1) = 'V' THEN 'Preventive'
        WHEN LEFT({{ diagnosis_code }}, 1) = 'E' THEN 'Injury/Trauma'
        ELSE 'Other'
    END
{% endmacro %}
