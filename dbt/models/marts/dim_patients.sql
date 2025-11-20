WITH patient_data AS (
    SELECT
        *,
        -- Use a window function to find the patient's first encounter date
        MIN(encounter_date) OVER (PARTITION BY patient_id) AS first_encounter_date
    FROM {{ ref('stg_encounters') }}
),

final AS (
    SELECT
        p.patient_id,
        p.date_of_birth,
        p.insurance_plan,
        p.patient_age,
        p.pcp_id,
        CASE
            WHEN p.patient_age >= 65 THEN TRUE
            WHEN p.insurance_plan ILIKE '%MEDICARE%' THEN TRUE
            ELSE FALSE
        END AS is_high_risk_patient
    FROM {{ ref('stg_patients') }} p
)

SELECT * FROM final
