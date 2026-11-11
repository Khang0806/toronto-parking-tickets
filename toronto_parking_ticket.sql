-- 1. CREATE TABLE
CREATE TABLE IF NOT EXISTS parking.raw_parking_tickets(
    tag_number_masked      TEXT,
    date_of_infraction     TEXT,
    infraction_code        TEXT,
    infraction_description TEXT,
    set_fine_amount        TEXT,
    time_of_infraction     TEXT,
    location1              TEXT,
    location2              TEXT,
    location3              TEXT,
    location4              TEXT,
    province               TEXT,
    source_file			   TEXT
);
--2. Check data
SELECT LEFT(date_of_infraction, 4) as year,
		COUNT(*) as n_rows,
		COUNT(DISTINCT source_file) as n_files
FROM parking.raw_parking_tickets
GROUP BY 1
ORDER BY 1;


-- 3. Clean Data
DROP TABLE IF EXISTS parking.clean_parking_tickets;
CREATE TABLE parking.clean_parking_tickets AS
WITH base AS (
	SELECT
		TRIM(date_of_infraction) AS d_raw,
		TRIM(infraction_code) AS infraction_code,
		UPPER(TRIM(infraction_description)) AS infraction_description,
		TRIM(set_fine_amount) AS f_raw,
		LPAD(TRIM(time_of_infraction), 4, '0') AS t_raw,
		TRIM(location1) AS location1,
		UPPER(REGEXP_REPLACE(TRIM(location2), '\s+', ' ','g')) AS address,
		UPPER(TRIM(province)) AS province,
		source_file
FROM parking.raw_parking_tickets)

SELECT
	CASE WHEN d_raw ~ '^\d{8}$' THEN to_date(d_raw, 'YYYYMMDD') END AS infraction_date,
	CASE WHEN t_raw ~ '^([01]\d|2[0-3])[0-5]\d$' THEN to_timestamp(t_raw, 'HH24MI')::TIME END AS infraction_time,
	CASE WHEN f_raw ~ '^\d+(\.\d+)?$' THEN f_raw::NUMERIC(10,2) END AS fine_amount,
	infraction_code,
	infraction_description,
	address,
	TRIM(REGEXP_REPLACE(address, '^\d+\s+', '')) AS street,
	province,
	source_file
FROM base;

-- FINE REVENUE CHANGED OVER MONTHS AND YEARS
CREATE OR REPLACE VIEW parking.v_monthly_revenue AS
WITH monthly AS(
SELECT
	DATE_TRUNC('month', infraction_date)::DATE AS month,
	COUNT(*) AS n_tickets,
	SUM(fine_amount) AS REVENUE
FROM parking.clean_parking_tickets
WHERE infraction_date IS NOT NULL
GROUP BY month)

SELECT
	month,
	n_tickets,
	REVENUE,
	LAG(REVENUE,12) OVER(ORDER BY month) AS REVENUE_LAST_YEAR
FROM monthly
ORDER BY month;

-- MOST COMMON FINE TYPE AND ITS TREND OVER YEARS
CREATE OR REPLACE VIEW parking.v_top_infraction_by_year AS
WITH yearly AS
(SELECT
	infraction_code,
	infraction_description,
	EXTRACT(YEAR FROM infraction_date)::INT AS yr,
	COUNT(*) AS n_tickets,
	ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY EXTRACT(YEAR FROM infraction_date)::INT), 2) AS pct,
	RANK() OVER(PARTITION BY EXTRACT(YEAR FROM infraction_date)::INT ORDER BY COUNT(*) DESC) AS RANK
FROM parking.clean_parking_tickets
WHERE infraction_date IS NOT NULL
GROUP BY infraction_code, infraction_description, yr)

SELECT
	infraction_code, infraction_description, yr, n_tickets, pct
FROM yearly
WHERE RANK = 1;


-- TOP TICKETED ADDRESS PER YEAR, WITH PEAK HOUR AND PEAK DAY
CREATE OR REPLACE VIEW parking.v_top_address_by_year AS
WITH base AS (
SELECT
	address,
	EXTRACT(YEAR FROM infraction_date)::INT AS yr,
	EXTRACT(HOUR FROM infraction_time)::INT as hr,
	TO_CHAR(infraction_date, 'FMDay') AS dow_name,
	fine_amount
FROM parking.clean_parking_tickets
WHERE infraction_date BETWEEN '2022-01-01' AND '2024-12-31' AND address IS NOT NULL AND address <> ''),
-- TOP ADDRESS GET FINED EACH YEAR
top_address AS (
SELECT yr, address, n_tickets, total_fine, avg_fine
FROM (
	SELECT 
		yr,
		address,
		COUNT(*) AS n_tickets,
		SUM(fine_amount) AS total_fine,
		ROUND(AVG(fine_amount),2) AS avg_fine,
		ROW_NUMBER() OVER(PARTITION BY yr ORDER BY COUNT(*) DESC, address) AS rn
	FROM base
	GROUP BY yr, address) x
	WHERE rn = 1),
-- PEAK FINE HOUR
peak_hour AS (
SELECT yr, address, hr, n 
FROM (
	SELECT
		b.yr,
		b.address,
		b.hr,
		COUNT(*) AS n,
		ROW_NUMBER() OVER(PARTITION BY b.yr, b.address ORDER BY COUNT(*) DESC, b.hr) as rn
	FROM base b
	JOIN top_address T ON b.yr = t.yr AND b.address = t.address
	WHERE b.hr IS NOT NULL
	GROUP BY b.hr, b.address, b.yr
		) x WHERE rn = 1),
-- DAYS OF WEEK PEAK FINE
peak_days AS (
SELECT yr, dow_name, address, n 
FROM (
	SELECT
		b.yr,
		b.address,
		b.dow_name,
		COUNT(*) AS n,
		ROW_NUMBER() OVER(PARTITION BY b.yr, b.address ORDER BY COUNT(*) DESC, b.dow_name) AS rn
	FROM base b
	JOIN top_address t ON b.yr = t.yr AND b.address = t.address
	GROUP BY b.yr, b.address, b.dow_name) x 
	WHERE rn = 1)

SELECT 
	t.address,
	t.yr,
	t.n_tickets,
	t.total_fine,
	t.avg_fine,
	h.hr AS peak_hour,
	h.n AS tickets_in_peak_hour,
	d.dow_name AS peak_day,
	d.n AS tickets_on_peak_day
FROM top_address t
JOIN peak_hour h USING (yr, address)
JOIN peak_days d USING (yr, address)
ORDER BY t.yr;


-- CREATE VIEW FOR POWER BI

-- DAILY SUMMARY
CREATE OR REPLACE VIEW parking.v_daily_summary AS
SELECT
      infraction_date
    , infraction_code
    , street
    , COUNT(*)         AS n_tickets
    , SUM(fine_amount) AS revenue
    , EXTRACT(YEAR FROM infraction_date) as yr,
    DATE_TRUNC('month', infraction_date) as month
FROM parking.clean_parking_tickets
WHERE infraction_date IS NOT NULL
GROUP BY yr, month, infraction_date, infraction_code, street;


-- DIM DATE
CREATE OR REPLACE VIEW parking.dim_date AS
SELECT
      d::DATE                       AS date
    , EXTRACT(YEAR   FROM d)::INT   AS yr
    , EXTRACT(MONTH  FROM d)::INT   AS month_num
    , TO_CHAR(d, 'Mon')             AS month_name
    , EXTRACT(ISODOW FROM d)::INT   AS dow_num
    , TO_CHAR(d, 'FMDay')           AS dow_name
FROM generate_series('2022-01-01'::DATE, '2024-12-31'::DATE, INTERVAL '1 day') AS d;

-- DIM INFRACTION
CREATE OR REPLACE VIEW parking.dim_infraction AS
SELECT DISTINCT ON (infraction_code)
      infraction_code
    , infraction_description
FROM (
    SELECT infraction_code, infraction_description, COUNT(*) AS n
    FROM parking.clean_parking_tickets
    WHERE infraction_code IS NOT NULL
    GROUP BY infraction_code, infraction_description
) x
ORDER BY infraction_code, n DESC;

-- DIM YEAR
CREATE OR REPLACE VIEW parking.v_dim_year AS
SELECT DISTINCT EXTRACT(YEAR FROM infraction_date)::INT AS yr
FROM parking.clean_parking_tickets
WHERE infraction_date IS NOT NULL;

	