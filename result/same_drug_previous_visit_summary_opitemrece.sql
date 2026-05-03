/*
  Summary: count visits on a given date that received the same drugs as the
  previous drug visit for the same HN, limited to a lookback window.

  This version follows the HOSxP schema guide:
    opitemrece -> opi_dispense -> opi_dispense_item_type

  Expected joins:
    opitemrece.hos_guid = opi_dispense.hos_guid
    opi_dispense.opi_dispense_item_type_id =
        opi_dispense_item_type.opi_dispense_item_type_id

  Parameters:
    @visit_date    Target visit date, e.g. '2025-10-11'
    @lookback_days Number of days to look back for the previous drug visit.

  Example:
    SET @visit_date = '2025-10-11';
    SET @lookback_days = 100;
    SOURCE same_drug_previous_visit_summary_opitemrece.sql;
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
        oi.hn
    FROM opitemrece oi
    INNER JOIN opi_dispense d
        ON d.hos_guid = oi.hos_guid
    INNER JOIN params p
        ON oi.vstdate = p.target_date
    WHERE COALESCE(oi.hn, '') <> ''
      AND COALESCE(oi.vn, '') <> ''
),
visit_drug_qty AS (
    SELECT
        oi.hn,
        oi.vn,
        oi.vstdate,
        COALESCE(oi.vsttime, '00:00:00') AS vsttime,
        d.icode,
        SUM(d.qty) AS qty,
        MAX(d.opi_dispense_item_type_id) AS opi_dispense_item_type_id,
        MAX(t.opi_dispense_item_type_name) AS opi_dispense_item_type_name
    FROM opitemrece oi
    INNER JOIN target_hn th
        ON th.hn = oi.hn
    INNER JOIN params p
        ON oi.vstdate BETWEEN p.start_date AND p.target_date
    INNER JOIN opi_dispense d
        ON d.hos_guid = oi.hos_guid
    LEFT JOIN opi_dispense_item_type t
        ON t.opi_dispense_item_type_id = d.opi_dispense_item_type_id
    WHERE COALESCE(oi.hn, '') <> ''
      AND COALESCE(oi.vn, '') <> ''
    GROUP BY
        oi.hn,
        oi.vn,
        oi.vstdate,
        COALESCE(oi.vsttime, '00:00:00'),
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
        ) AS drug_qty_set,
        GROUP_CONCAT(
            CASE
                WHEN opi_dispense_item_type_id = 2
                  OR opi_dispense_item_type_name = 'ยาเดิม'
                THEN icode
                ELSE NULL
            END
            ORDER BY icode
            SEPARATOR ','
        ) AS old_drug_set
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
        old_drug_set,
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
            WHEN old_drug_set IS NOT NULL AND old_drug_set <> ''
            THEN 1
            ELSE 0
        END
    ) AS old_drug_marked_visit_count,
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
