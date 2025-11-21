SELECT
    encounter_id,
    patient_id,
    encounter_date,
    provider_id,
    primary_dx_code,
    place_of_service
    -- Add any necessary data type casting or simple cleaning here
FROM {{ source('raw_data', 'encounters') }}
