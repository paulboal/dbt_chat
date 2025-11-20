SELECT
    encounter_id,
    patient_id,
    encounter_date,
    provider_id,
    primary_dx_code
    -- Add any necessary data type casting or simple cleaning here
FROM {{ source('raw_data', 'encounters') }}
