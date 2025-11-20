SELECT
    e.encounter_id,
    e.patient_id,
    e.encounter_date,
    e.provider_id,
    e.primary_dx_code,
    {{ get_dx_group('e.primary_dx_code') }} AS dx_group,
    DATEDIFF('day', LAG(e.encounter_date) OVER (PARTITION BY e.patient_id ORDER BY e.encounter_date), e.encounter_date) AS days_since_last_encounter
FROM {{ source('raw_data', 'encounters') }} e
