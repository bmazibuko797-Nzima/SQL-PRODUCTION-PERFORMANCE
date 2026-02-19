-- ===========================================================
-- View: stg_productivity
-- Purpose: Prepares a staging table with batch-level productivity metrics.
--          Calculates accurate start and end timestamps, including handling overnight shifts.
-- ===========================================================

CREATE VIEW stg_productivity AS
SELECT
    batch,                       -- Unique batch identifier
    operator,                    -- Operator responsible for the batch
    product,                     -- Product being produced
    date,                        -- Production date
    TIMESTAMP(date, start_time) AS start_ts,  -- Combine date and start_time into a single timestamp

    -- Adjust end timestamp for overnight shifts (if end_time < start_time, assume next day)
    CASE
        WHEN TIMESTAMP(date, end_time) < TIMESTAMP(date, start_time)
        THEN TIMESTAMP(DATE_ADD(date, INTERVAL 1 DAY), end_time)
        ELSE TIMESTAMP(date, end_time)
    END AS end_ts,

    -- Calculate total batch duration in minutes, considering overnight shifts
    CASE
        WHEN TIMESTAMP(date, end_time) < TIMESTAMP(date, start_time)
        THEN TIMESTAMPDIFF(
               MINUTE,
               TIMESTAMP(date, start_time),
               TIMESTAMP(DATE_ADD(date, INTERVAL 1 DAY), end_time)
             )
        ELSE TIMESTAMPDIFF(
               MINUTE,
               TIMESTAMP(date, start_time),
               TIMESTAMP(date, end_time)
             )
    END AS batch_minutes
FROM line_productivity;


-- ===========================================================
-- View: tr_downtime_long
-- Purpose: Transforms downtime table from wide format to long format.
--          Each factor (factor1…factor12) is represented as a separate row with minutes.
-- ===========================================================

CREATE VIEW tr_downtime_long AS
SELECT batch, 1 AS factor, factor1 AS minutes FROM line_downtime
UNION ALL SELECT batch, 2, factor2 FROM line_downtime
UNION ALL SELECT batch, 3, factor3 FROM line_downtime
UNION ALL SELECT batch, 4, factor4 FROM line_downtime
UNION ALL SELECT batch, 5, factor5 FROM line_downtime
UNION ALL SELECT batch, 6, factor6 FROM line_downtime
UNION ALL SELECT batch, 7, factor7 FROM line_downtime
UNION ALL SELECT batch, 8, factor8 FROM line_downtime
UNION ALL SELECT batch, 9, factor9 FROM line_downtime
UNION ALL SELECT batch, 10, factor10 FROM line_downtime
UNION ALL SELECT batch, 11, factor11 FROM line_downtime
UNION ALL SELECT batch, 12, factor12 FROM line_downtime;


-- ===========================================================
-- View: kpi_master
-- Purpose: Aggregates production and downtime data to calculate KPIs.
--          Computes efficiency, availability, and performance loss for each batch.
-- ===========================================================

CREATE VIEW kpi_master AS
SELECT
    s.batch,                     -- Batch identifier
    s.date,                      -- Production date
    s.operator,                  -- Operator responsible
    p.product,                   -- Product code
    p.flavor,                     -- Product flavor
    p.size,                       -- Product size
    s.batch_minutes,             -- Total minutes of the batch
    p.min_batch_time,            -- Standard/minimum expected batch time

    -- Total downtime in minutes per batch
    COALESCE(SUM(d.minutes),0) AS total_downtime,

    -- Downtime caused specifically by operator errors
    COALESCE(SUM(
        CASE 
            WHEN f.`Operator Error` = 'Yes' 
            THEN d.minutes 
            ELSE 0 
        END
    ),0) AS operator_error_minutes,

    -- Efficiency (%) = minimum batch time divided by actual batch minutes
    ROUND(
        (p.min_batch_time / NULLIF(s.batch_minutes,0)) * 100,
    2) AS efficiency_pct,

    -- Availability (%) = productive time (batch_minutes - downtime) / batch_minutes
    ROUND(
        (s.batch_minutes - COALESCE(SUM(d.minutes),0)) 
        / NULLIF(s.batch_minutes,0) * 100,
    2) AS availability_pct,

    -- Performance loss (minutes) = excess time beyond minimum batch time
    GREATEST(
        s.batch_minutes - p.min_batch_time,
    0) AS performance_loss

FROM stg_productivity s
JOIN products p 
    ON s.product = p.product    -- Join with product master to get product attributes

LEFT JOIN tr_downtime_long d 
    ON s.batch = d.batch        -- Attach downtime data

LEFT JOIN downtime_factors f 
    ON d.factor = f.factor      -- Attach factor attributes (e.g., operator error)

-- Group by all non-aggregated fields to compute KPIs at batch level
GROUP BY
    s.batch,
    s.date,
    s.operator,
    p.product,
    p.flavor,
    p.size,
    s.batch_minutes,
    p.min_batch_time;

