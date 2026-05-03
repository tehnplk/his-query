/*
  Summary: count visits on a given date that received the same drugs as the
  previous drug visit for the same HN, limited to a lookback window.

  Parameters:
    @visit_date    Target visit date, e.g. '2025-10-11'
    @lookback_days Number of days to look back for the previous drug visit.

  Example:
    SET @visit_date = '2025-10-11';
    SET @lookback_days = 100;
    SOURCE same_drug_previous_visit_summary.sql;
*/

SET @visit_date = DATE(COALESCE(@visit_date, '2025-10-11'));
SET @lookback_days = COALESCE(@lookback_days, 100);

WITH params AS (
    SELECT
        @visit_date AS target_date,
        DATE_SUB(@visit_date, INTERVAL @lookback_days DAY) AS start_date
),
target_hn AS (
    SELECT DISTINCT
        o.hn
    FROM ovst o
    INNER JOIN opi_dispense_dru od
        ON od.vn = o.vn
    INNER JOIN params p
        ON o.vstdate = p.target_date
    WHERE COALESCE(o.hn, '') <> ''
),
visit_drug_qty AS (
    SELECT
        o.hn,
        o.vn,
        o.vstdate,
        o.vsttime,
        d.icode,
        SUM(d.qty) AS qty
    FROM ovst o
    INNER JOIN target_hn th
        ON th.hn = o.hn
    INNER JOIN params p
        ON o.vstdate BETWEEN p.start_date AND p.target_date
    INNER JOIN opi_dispense_dru od
        ON od.vn = o.vn
    INNER JOIN opi_dispense d
        ON d.opi_dispense_id = od.opi_dispense_id
    WHERE COALESCE(o.hn, '') <> ''
    GROUP BY
        o.hn,
        o.vn,
        o.vstdate,
        o.vsttime,
        d.icode
),
visit_sets AS (
    SELECT
        hn,
        vn,
        vstdate,
        vsttime,
        GROUP_CONCAT(icode ORDER BY icode SEPARATOR ',') AS drug_set,
        GROUP_CONCAT(
            CONCAT(
                icode,
                ':',
                TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(qty AS CHAR)))
            )
            ORDER BY icode
            SEPARATOR ','
        ) AS drug_qty_set
    FROM visit_drug_qty
    GROUP BY
        hn,
        vn,
        vstdate,
        vsttime
),
visit_compare AS (
    SELECT
        hn,
        vn,
        vstdate,
        vsttime,
        drug_set,
        drug_qty_set,
        LAG(vn) OVER (
            PARTITION BY hn
            ORDER BY vstdate, vsttime, vn
        ) AS prev_vn,
        LAG(vstdate) OVER (
            PARTITION BY hn
            ORDER BY vstdate, vsttime, vn
        ) AS prev_vstdate,
        LAG(drug_set) OVER (
            PARTITION BY hn
            ORDER BY vstdate, vsttime, vn
        ) AS prev_drug_set,
        LAG(drug_qty_set) OVER (
            PARTITION BY hn
            ORDER BY vstdate, vsttime, vn
        ) AS prev_drug_qty_set
    FROM visit_sets
)
SELECT
    @visit_date AS visit_date,
    @lookback_days AS lookback_days,
    COUNT(*) AS visit_count_on_date,
    SUM(
        CASE
            WHEN prev_vn IS NOT NULL
             AND DATEDIFF(vstdate, prev_vstdate) <= @lookback_days
             AND drug_set = prev_drug_set
            THEN 1
            ELSE 0
        END
    ) AS same_drug_count,
    SUM(
        CASE
            WHEN prev_vn IS NOT NULL
             AND DATEDIFF(vstdate, prev_vstdate) <= @lookback_days
             AND drug_qty_set = prev_drug_qty_set
            THEN 1
            ELSE 0
        END
    ) AS same_drug_and_qty_count,
    SUM(
        CASE
            WHEN prev_vn IS NULL
              OR DATEDIFF(vstdate, prev_vstdate) > @lookback_days
            THEN 1
            ELSE 0
        END
    ) AS no_previous_drug_visit_in_lookback_count
FROM visit_compare
WHERE vstdate = @visit_date;
