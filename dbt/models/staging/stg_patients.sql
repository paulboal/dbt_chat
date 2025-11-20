SELECT
    patient_id,
    date_of_birth,
    insurance_plan,
    pcp_id,
    DATEDIFF('year', date_of_birth, CURRENT_DATE()) AS patient_age
FROM {{ source('raw_data', 'patients') }}
