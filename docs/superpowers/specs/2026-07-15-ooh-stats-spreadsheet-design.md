# OOH Stats Spreadsheet — Design

Date: 2026-07-15

## Purpose

Generate CSV files summarising OpsGenie alerts tagged `OOH` (out of hours) over
the past 3 years, to support reporting and a rough estimate of TOIL claimed.

Deliverables:

1. Daily count of OOH alerts.
2. Monthly totals of OOH alerts.
3. Monthly estimate of TOIL that was probably claimed.

## Script

New script: `ooh-stats.rb`, following the conventions of the existing
`stats.rb` (HTTParty, dotenv, offset pagination) and `calculate-toil.rb`
(sleeping/waking TOIL logic).

## Configuration (`.env`)

* `OPSGENIE_API_KEY` — required. Exit with an error if unset.
* `TOIL_SLEEPING_HOURS` — TOIL hours per de-duped acknowledged `sleepinghours`
  OOH alert. Defaults to `0.0`.
* `TOIL_WAKING_HOURS` — TOIL hours per de-duped acknowledged `wakinghours` OOH
  alert. Defaults to `0.0`.
* `YEARS_BACK` — how many years back to look. Defaults to `3`.

## Data fetching

* Endpoint: `https://api.opsgenie.com/v2/alerts`.
* Query filters alerts tagged `OOH` within the date range
  (`createdAt >= start AND createdAt < end AND tags:(OOH)`), using the same
  `dd-MM-yyyy'T'HH:mm:ss` date format as `stats.rb`.
* Range: from midnight `YEARS_BACK` years ago, up to today.
* **Chunked by calendar month.** OpsGenie's offset pagination is capped
  (`offset + limit <= 20000`); 3 years of OOH alerts could exceed this in a
  single query. Iterating one month at a time keeps each paginated window well
  under the ceiling. Within each month, paginate with `limit=100` and an
  incrementing `offset` until an empty page is returned.
* Abort with the response body and a non-zero exit code on any non-200
  response, matching `stats.rb`.

## Processing

Collect all OOH alerts once, then produce three aggregations.

### 1. Daily counts

* Bucket each alert by the date portion of its `createdAt` (UTC as returned by
  the API, parsed with `Time.parse`).
* Emit a row for **every** calendar day in the range, inclusive of days with
  zero OOH alerts (count `0`).

### 2. Monthly totals

* Sum OOH alert counts per `YYYY-MM`.
* Emit a row for every month in the range.

### 3. Monthly TOIL (total only)

Reuse the `calculate-toil.rb` approach:

* Consider only alerts where `acknowledged` is true.
* Determine the acknowledger via `alert['report']['acknowledgedBy']`.
* If the alert's tags include `sleepinghours`, the rate is
  `TOIL_SLEEPING_HOURS`; else if they include `wakinghours`, the rate is
  `TOIL_WAKING_HOURS`; otherwise the alert contributes no TOIL.
* De-dupe per acknowledger and category: an alert is only counted if it is more
  than 30 minutes (1800s) after that user's last counted alert of the same
  category. This mirrors the existing script's noise reduction.
* Sum the resulting TOIL per month into a single total (not broken down per
  user).
* Emit a row for every month in the range (TOIL `0.0` where none).

## Output files (CSV, Ruby stdlib `csv`)

Written to the current working directory:

* `ooh_daily_counts.csv` — header `date,count`; `date` as `YYYY-MM-DD`.
* `ooh_monthly_totals.csv` — header `month,count`; `month` as `YYYY-MM`.
* `ooh_monthly_toil.csv` — header `month,toil_hours`; `month` as `YYYY-MM`.

## Out of scope

* Per-user TOIL breakdown (explicitly total-only).
* Weekly TOIL (superseded by monthly at user request).
* Business-unit or client breakdowns (that is `stats.rb`'s job).
* A true `.xlsx` workbook (CSV chosen; no new gems).

## README

Add an `ooh-stats.rb` section documenting usage and the environment variables.
