# Toronto Parking Tickets Analysis (2022–2024)

SQL + Power BI analysis of 6.2M parking tickets issued in the City of Toronto, built on PostgreSQL and the City's open data.

![Dashboard](images/dashboard.png)

## Questions
1. How did parking ticket revenue change month by month across 2022–2024?
2. Which infraction types are most common, and how did their share change by year?
3. Where are drivers ticketed the most, and when (peak hour and day)?

## Data
- Source: [City of Toronto Open Data – Parking Tickets](https://open.toronto.ca/dataset/parking-tickets/)
- Scope: 2022–2024, about 6.2M tickets across 33 CSV files
- Raw files are not included in this repo because of their size. Download them from the link above.

## Tech Stack
PostgreSQL · DBeaver · Python (psycopg2) · Power BI

## Pipeline
1. **Load** (`python/load_data.py`): validates the header of every CSV before loading, skips blank leading lines, falls back to WIN1252 encoding when UTF-8 fails, and bulk-loads each file with `COPY`. A `source_file` column tracks which file each row came from.
2. **Raw layer** (`raw_parking_tickets`): every column stored as `TEXT`, so a single malformed row cannot break the load.
3. **Clean layer** (`clean_parking_tickets`):
   - Dates (`YYYYMMDD`) and times (`HHMM`, with missing leading zeros restored using `LPAD`) are validated with regex before casting. Invalid values become `NULL` instead of failing the whole query.
   - Addresses are trimmed, upper-cased and whitespace-normalized, and house numbers are stripped to derive a `street` column.
4. **Analysis views**: CTEs, window functions (`LAG`, `RANK`, `ROW_NUMBER`, `SUM() OVER`) and multi-step subqueries.
5. **Star schema for Power BI**: fact table `v_daily_summary` with `dim_date`, `dim_infraction` and `v_dim_year`. `dim_infraction` uses `DISTINCT ON` to keep a single description per infraction code.

## Key Findings
- **Totals:** 6.225M tickets, $364.7M in fines, 197 infraction types, $58.59 average fine.
- **Fewer tickets, more revenue in 2024.** From August to November 2024, ticket volume was lower than in the same months of 2023, yet monthly revenue was higher. This matches the sharp rise in the average fine in 2024.
- **4700 Keele St (York University) was the most-ticketed address in all three years.** Fine revenue at this address rose from $848K (2022) to $1.44M (2023) and $2.76M (2024). Its average fine roughly doubled in 2024 ($36.09 → $78.53), and Tuesday was the peak day in every year.
- The cause of the 2024 increase in average fine (rate changes vs. a shift in infraction mix) was not investigated in this project.

## Limitations
- The data shows **where tickets were issued**, not where violations actually happen. Hotspots may reflect where enforcement officers patrol more often.
- Addresses are not fully standardized (`ST` vs `STREET`, typos, intersections), so some hotspots may be split across several spellings.
- The "Top Address" table is pre-computed in SQL and does not respond to dashboard slicers.

## Repo Structure
```
sql/          setup, cleaning, analysis and view scripts
python/       CSV loader
dashboard/    Power BI file (.pbix)
images/       dashboard screenshot
```
