# OOH Stats Spreadsheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ooh-stats.rb`, a Ruby script that fetches 3 years of OpsGenie `OOH`-tagged alerts and writes three CSVs: daily counts, monthly totals, and a monthly TOIL estimate.

**Architecture:** A single script split into pure functions (date-range generation, aggregation, TOIL calculation) plus an API-fetch section and a CSV-writing section. Pure functions are tested inline with `ruby -e` assertions so no test framework is introduced, matching the repo's existing zero-test-harness style. The `__FILE__ == $0` guard lets the functions be required for testing without triggering API calls.

**Tech Stack:** Ruby, HTTParty (already present via `opsgenie-schedule`), dotenv, Ruby stdlib `csv`/`date`/`time`.

## Global Constraints

- Ruby style must match existing scripts: 2-space indent, `require 'dotenv/load'`, HTTParty for HTTP, `GenieKey #{OPSGENIE_API_KEY}` auth header.
- OpsGenie date format in queries: `%d-%m-%YT%H:%M:%S` (verbatim, as in `stats.rb`).
- OpsGenie base URL: `https://api.opsgenie.com/v2/alerts`; pagination `LIMIT = 100`.
- Fetch is chunked per calendar month to stay under OpsGenie's `offset + limit <= 20000` ceiling.
- TOIL logic mirrors `calculate-toil.rb`: acknowledged alerts only; `sleepinghours` tag → `TOIL_SLEEPING_HOURS`, else `wakinghours` tag → `TOIL_WAKING_HOURS`; per-user-per-category de-dupe with a 1800-second gap.
- Env vars: `OPSGENIE_API_KEY` (required), `TOIL_SLEEPING_HOURS` (default `0.0`), `TOIL_WAKING_HOURS` (default `0.0`), `YEARS_BACK` (default `3`).
- Output files in CWD: `ooh_daily_counts.csv` (`date,count`), `ooh_monthly_totals.csv` (`month,count`), `ooh_monthly_toil.csv` (`month,toil_hours`).

---

### Task 1: Script scaffold, config loading, and month-window generation

**Files:**
- Create: `ooh-stats.rb`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `month_windows(start_date, end_date)` → `Array` of `[Date, Date]` pairs, each `[first_of_month, first_of_next_month]`, covering `start_date` up to (but not including) `end_date`. First window may start mid-month at `start_date`; last window ends at `end_date`.
  - Constants `BASE_URL` (String), `LIMIT` (Integer `100`).
  - Reads `OPSGENIE_API_KEY`, `TOIL_SLEEPING_HOURS`, `TOIL_WAKING_HOURS`, `YEARS_BACK` from ENV.

- [ ] **Step 1: Write the failing test**

Create `ooh-stats.rb` empty for now, then write the test as a standalone file check:

```bash
cat > /tmp/test_month_windows.rb <<'RUBY'
require_relative '/Users/bob/git/dxw/opsgenie-tools/ooh-stats.rb'
require 'date'

w = month_windows(Date.new(2024, 1, 15), Date.new(2024, 3, 10))
raise "expected 3 windows, got #{w.size}" unless w.size == 3
raise "w0 bad: #{w[0].inspect}" unless w[0] == [Date.new(2024,1,15), Date.new(2024,2,1)]
raise "w1 bad: #{w[1].inspect}" unless w[1] == [Date.new(2024,2,1), Date.new(2024,3,1)]
raise "w2 bad: #{w[2].inspect}" unless w[2] == [Date.new(2024,3,1), Date.new(2024,3,10)]

w2 = month_windows(Date.new(2024, 1, 1), Date.new(2024, 2, 1))
raise "single month bad: #{w2.inspect}" unless w2 == [[Date.new(2024,1,1), Date.new(2024,2,1)]]

puts "month_windows OK"
RUBY
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby /tmp/test_month_windows.rb`
Expected: FAIL with a `NoMethodError` / `undefined method 'month_windows'` (file is empty).

- [ ] **Step 3: Write minimal implementation**

Write `ooh-stats.rb`:

```ruby
#!/usr/bin/env ruby
# Generate CSV stats for OpsGenie alerts tagged OOH over the past N years.
# Produces three CSVs in the current directory:
#   ooh_daily_counts.csv   (date,count)   - one row per calendar day
#   ooh_monthly_totals.csv (month,count)  - one row per month
#   ooh_monthly_toil.csv   (month,toil_hours) - monthly TOIL estimate
#
# Environment variables (may be set in a .env file):
#   OPSGENIE_API_KEY    required
#   TOIL_SLEEPING_HOURS TOIL per de-duped acknowledged sleepinghours alert (default 0.0)
#   TOIL_WAKING_HOURS   TOIL per de-duped acknowledged wakinghours alert (default 0.0)
#   YEARS_BACK          how many years back to look (default 3)
require 'dotenv/load'
require 'httparty'
require 'json'
require 'csv'
require 'date'
require 'time'
require 'uri'

BASE_URL = "https://api.opsgenie.com/v2/alerts"
LIMIT = 100

# Build [start, next] Date pairs, one per calendar month spanned by the range.
# The first pair starts at start_date; the last pair ends at end_date.
def month_windows(start_date, end_date)
  windows = []
  cursor = start_date
  while cursor < end_date
    first_of_next = if cursor.month == 12
                      Date.new(cursor.year + 1, 1, 1)
                    else
                      Date.new(cursor.year, cursor.month + 1, 1)
                    end
    window_end = [first_of_next, end_date].min
    windows << [cursor, window_end]
    cursor = first_of_next
  end
  windows
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby /tmp/test_month_windows.rb`
Expected: `month_windows OK`

- [ ] **Step 5: Commit**

```bash
git add ooh-stats.rb
git commit -m "Add ooh-stats.rb scaffold with month window generation"
```

---

### Task 2: Daily counts aggregation

**Files:**
- Modify: `ooh-stats.rb`

**Interfaces:**
- Consumes: `month_windows` (not directly used here).
- Produces:
  - `daily_counts(alerts, start_date, end_date)` → `Array` of `[String date "YYYY-MM-DD", Integer count]`, one row for every calendar day from `start_date` up to but not including `end_date`, zeros included, in ascending date order. `alerts` is an `Array` of Hashes each having a `"createdAt"` String parseable by `Time.parse`.

- [ ] **Step 1: Write the failing test**

```bash
cat > /tmp/test_daily.rb <<'RUBY'
require_relative '/Users/bob/git/dxw/opsgenie-tools/ooh-stats.rb'
require 'date'

alerts = [
  {"createdAt" => "2024-01-01T10:00:00.000Z"},
  {"createdAt" => "2024-01-01T23:30:00.000Z"},
  {"createdAt" => "2024-01-03T08:00:00.000Z"},
]
rows = daily_counts(alerts, Date.new(2024,1,1), Date.new(2024,1,4))
raise "size #{rows.size}" unless rows.size == 3
raise "d1 #{rows[0].inspect}" unless rows[0] == ["2024-01-01", 2]
raise "d2 #{rows[1].inspect}" unless rows[1] == ["2024-01-02", 0]
raise "d3 #{rows[2].inspect}" unless rows[2] == ["2024-01-03", 1]
puts "daily_counts OK"
RUBY
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby /tmp/test_daily.rb`
Expected: FAIL with `undefined method 'daily_counts'`.

- [ ] **Step 3: Write minimal implementation**

Add to `ooh-stats.rb` (after `month_windows`):

```ruby
# Count alerts per calendar day, emitting a row for every day in the range
# (inclusive of days with zero alerts).
def daily_counts(alerts, start_date, end_date)
  counts = Hash.new(0)
  alerts.each do |alert|
    day = Time.parse(alert["createdAt"]).strftime("%Y-%m-%d")
    counts[day] += 1
  end

  rows = []
  day = start_date
  while day < end_date
    key = day.strftime("%Y-%m-%d")
    rows << [key, counts[key]]
    day += 1
  end
  rows
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby /tmp/test_daily.rb`
Expected: `daily_counts OK`

- [ ] **Step 5: Commit**

```bash
git add ooh-stats.rb
git commit -m "Add daily OOH alert count aggregation"
```

---

### Task 3: Monthly totals aggregation

**Files:**
- Modify: `ooh-stats.rb`

**Interfaces:**
- Consumes: `alerts` array (same shape as Task 2).
- Produces:
  - `monthly_totals(alerts, start_date, end_date)` → `Array` of `[String month "YYYY-MM", Integer count]`, one row for every month spanned by the range (via `month_windows`), zeros included, ascending.

- [ ] **Step 1: Write the failing test**

```bash
cat > /tmp/test_monthly.rb <<'RUBY'
require_relative '/Users/bob/git/dxw/opsgenie-tools/ooh-stats.rb'
require 'date'

alerts = [
  {"createdAt" => "2024-01-05T10:00:00.000Z"},
  {"createdAt" => "2024-01-20T10:00:00.000Z"},
  {"createdAt" => "2024-03-02T10:00:00.000Z"},
]
rows = monthly_totals(alerts, Date.new(2024,1,1), Date.new(2024,4,1))
raise "size #{rows.size}" unless rows.size == 3
raise "m1 #{rows[0].inspect}" unless rows[0] == ["2024-01", 2]
raise "m2 #{rows[1].inspect}" unless rows[1] == ["2024-02", 0]
raise "m3 #{rows[2].inspect}" unless rows[2] == ["2024-03", 1]
puts "monthly_totals OK"
RUBY
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby /tmp/test_monthly.rb`
Expected: FAIL with `undefined method 'monthly_totals'`.

- [ ] **Step 3: Write minimal implementation**

Add to `ooh-stats.rb`:

```ruby
# Count alerts per calendar month, one row per month in the range.
def monthly_totals(alerts, start_date, end_date)
  counts = Hash.new(0)
  alerts.each do |alert|
    month = Time.parse(alert["createdAt"]).strftime("%Y-%m")
    counts[month] += 1
  end

  month_windows(start_date, end_date).map do |window_start, _window_end|
    key = window_start.strftime("%Y-%m")
    [key, counts[key]]
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby /tmp/test_monthly.rb`
Expected: `monthly_totals OK`

- [ ] **Step 5: Commit**

```bash
git add ooh-stats.rb
git commit -m "Add monthly OOH alert totals aggregation"
```

---

### Task 4: Monthly TOIL aggregation

**Files:**
- Modify: `ooh-stats.rb`

**Interfaces:**
- Consumes: `alerts` array; each alert may additionally have `"acknowledged"` (bool), `"tags"` (Array of String), and `"report" => {"acknowledgedBy" => String}`.
- Produces:
  - `monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate)` → `Array` of `[String month "YYYY-MM", Float toil_hours]`, one row per month in the range. Only acknowledged alerts with a `sleepinghours` or `wakinghours` tag contribute. Per acknowledger-and-category, an alert is skipped if within 1800s of that user's previous counted alert of the same category. Alerts must be processed in chronological order for de-dupe correctness.

- [ ] **Step 1: Write the failing test**

```bash
cat > /tmp/test_toil.rb <<'RUBY'
require_relative '/Users/bob/git/dxw/opsgenie-tools/ooh-stats.rb'
require 'date'

def ack(time, by, tag)
  {"createdAt" => time, "acknowledged" => true, "tags" => ["OOH", tag],
   "report" => {"acknowledgedBy" => by}}
end

alerts = [
  ack("2024-01-01T02:00:00.000Z", "alice", "sleepinghours"),
  ack("2024-01-01T02:10:00.000Z", "alice", "sleepinghours"), # within 30m, skip
  ack("2024-01-01T03:00:00.000Z", "alice", "sleepinghours"), # >30m, count
  ack("2024-01-10T20:00:00.000Z", "bob", "wakinghours"),
  {"createdAt" => "2024-02-05T02:00:00.000Z", "acknowledged" => false,
   "tags" => ["OOH", "sleepinghours"], "report" => {"acknowledgedBy" => "eve"}}, # not ack
  {"createdAt" => "2024-03-05T02:00:00.000Z", "acknowledged" => true,
   "tags" => ["OOH"], "report" => {"acknowledgedBy" => "eve"}}, # no time tag
]
rows = monthly_toil(alerts, Date.new(2024,1,1), Date.new(2024,4,1), 8.0, 4.0)
raise "size #{rows.size}" unless rows.size == 3
# Jan: alice 2 sleeping (16.0) + bob 1 waking (4.0) = 20.0
raise "m1 #{rows[0].inspect}" unless rows[0] == ["2024-01", 20.0]
raise "m2 #{rows[1].inspect}" unless rows[1] == ["2024-02", 0.0]
raise "m3 #{rows[2].inspect}" unless rows[2] == ["2024-03", 0.0]
puts "monthly_toil OK"
RUBY
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby /tmp/test_toil.rb`
Expected: FAIL with `undefined method 'monthly_toil'`.

- [ ] **Step 3: Write minimal implementation**

Add to `ooh-stats.rb`:

```ruby
# Estimate monthly TOIL from acknowledged OOH alerts, mirroring calculate-toil.rb:
# sleepinghours-tagged alerts use sleeping_rate, wakinghours use waking_rate.
# Per user and category, alerts within 1800s of the previous counted one are
# treated as duplicates and skipped.
def monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate)
  toil_by_month = Hash.new(0.0)
  # last_counted[user][category] = Time
  last_counted = Hash.new { |h, k| h[k] = Hash.new(Time.at(0)) }

  ordered = alerts.sort_by { |a| Time.parse(a["createdAt"]) }
  ordered.each do |alert|
    next unless alert["acknowledged"]
    tags = alert["tags"] || []
    category, rate =
      if tags.include?("sleepinghours")
        ["sleepinghours", sleeping_rate]
      elsif tags.include?("wakinghours")
        ["wakinghours", waking_rate]
      end
    next if category.nil?

    user = alert.dig("report", "acknowledgedBy")
    created = Time.parse(alert["createdAt"])
    next unless (created - last_counted[user][category]) > 1800

    last_counted[user][category] = created
    toil_by_month[created.strftime("%Y-%m")] += rate
  end

  month_windows(start_date, end_date).map do |window_start, _window_end|
    key = window_start.strftime("%Y-%m")
    [key, toil_by_month[key]]
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby /tmp/test_toil.rb`
Expected: `monthly_toil OK`

- [ ] **Step 5: Commit**

```bash
git add ooh-stats.rb
git commit -m "Add monthly TOIL estimation from acknowledged OOH alerts"
```

---

### Task 5: API fetch (per-month, paginated) and main runner

**Files:**
- Modify: `ooh-stats.rb`

**Interfaces:**
- Consumes: `month_windows`, `daily_counts`, `monthly_totals`, `monthly_toil`, `BASE_URL`, `LIMIT`.
- Produces:
  - `fetch_ooh_alerts(api_key, start_date, end_date)` → `Array` of alert Hashes, fetched one month at a time with offset pagination.
  - A `if __FILE__ == $0` block that reads config, validates the key, fetches, aggregates, and writes the three CSVs.

- [ ] **Step 1: Write the fetch function and main block**

Add to `ooh-stats.rb`:

```ruby
# Fetch all OOH-tagged alerts in [start_date, end_date), one month per query
# window to stay under OpsGenie's offset+limit <= 20000 ceiling.
def fetch_ooh_alerts(api_key, start_date, end_date)
  all_alerts = []
  month_windows(start_date, end_date).each do |window_start, window_end|
    offset = 0
    loop do
      formatted_start = Time.parse(window_start.to_s).strftime("%d-%m-%YT%H:%M:%S")
      formatted_end   = Time.parse(window_end.to_s).strftime("%d-%m-%YT%H:%M:%S")
      query = "createdAt >= '#{formatted_start}' AND createdAt < '#{formatted_end}' AND tags:(OOH)"
      url = "#{BASE_URL}?limit=#{LIMIT}&offset=#{offset}&query=#{URI.encode_www_form_component(query)}"
      response = HTTParty.get(url, headers: {
        "Authorization" => "GenieKey #{api_key}",
        "Content-Type"  => "application/json"
      })
      if response.code != 200
        puts "Error fetching alerts: #{response.body}"
        exit 1
      end
      alerts = JSON.parse(response.body)["data"] || []
      break if alerts.empty?
      all_alerts.concat(alerts)
      offset += LIMIT
    end
  end
  all_alerts
end

if __FILE__ == $0
  api_key = ENV['OPSGENIE_API_KEY']
  unless api_key
    puts "Error: Please set the OPSGENIE_API_KEY environment variable."
    exit 1
  end

  sleeping_rate = ENV['TOIL_SLEEPING_HOURS'] ? ENV['TOIL_SLEEPING_HOURS'].to_f : 0.0
  waking_rate   = ENV['TOIL_WAKING_HOURS'] ? ENV['TOIL_WAKING_HOURS'].to_f : 0.0
  years_back    = ENV['YEARS_BACK'] ? ENV['YEARS_BACK'].to_i : 3

  end_date   = Date.today + 1
  start_date = end_date.prev_year(years_back)

  puts "Fetching OOH alerts from #{start_date} to #{end_date}..."
  alerts = fetch_ooh_alerts(api_key, start_date, end_date)
  puts "Fetched #{alerts.size} OOH alerts."

  CSV.open("ooh_daily_counts.csv", "w") do |csv|
    csv << ["date", "count"]
    daily_counts(alerts, start_date, end_date).each { |row| csv << row }
  end

  CSV.open("ooh_monthly_totals.csv", "w") do |csv|
    csv << ["month", "count"]
    monthly_totals(alerts, start_date, end_date).each { |row| csv << row }
  end

  CSV.open("ooh_monthly_toil.csv", "w") do |csv|
    csv << ["month", "toil_hours"]
    monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate).each { |row| csv << row }
  end

  puts "Wrote ooh_daily_counts.csv, ooh_monthly_totals.csv, ooh_monthly_toil.csv"
end
```

- [ ] **Step 2: Verify the script loads and the missing-key guard works**

Run: `env -u OPSGENIE_API_KEY ruby ooh-stats.rb`
Expected: `Error: Please set the OPSGENIE_API_KEY environment variable.` and exit code 1.

- [ ] **Step 3: Re-run all prior unit tests to confirm no regressions**

Run: `for t in month_windows daily monthly toil; do ruby /tmp/test_$t.rb; done`
Expected: `month_windows OK`, `daily_counts OK`, `monthly_totals OK`, `monthly_toil OK`.

- [ ] **Step 4: Live smoke test (requires a real API key in .env)**

Run: `bundle exec ruby ooh-stats.rb`
Expected: prints fetch progress, the three CSV files exist in CWD, `ooh_daily_counts.csv` has ~ (365 * YEARS_BACK) + 1 data rows, headers correct.
Verify: `head -3 ooh_daily_counts.csv ooh_monthly_totals.csv ooh_monthly_toil.csv`

- [ ] **Step 5: Commit**

```bash
git add ooh-stats.rb
git commit -m "Add OOH alert fetching and CSV output to ooh-stats.rb"
```

---

### Task 6: README documentation

**Files:**
- Modify: `README.md` (add a section after the `stats.rb` section, before `## License`)

**Interfaces:**
- Consumes: nothing.
- Produces: user-facing docs. No code.

- [ ] **Step 1: Add the README section**

Insert before `## License` in `README.md`:

```markdown
### ooh-stats.rb

A script to generate a spreadsheet (three CSV files) of OpsGenie alerts tagged
`OOH` over the past few years. It writes:

* `ooh_daily_counts.csv` — number of OOH alerts per calendar day (zero-filled).
* `ooh_monthly_totals.csv` — number of OOH alerts per month.
* `ooh_monthly_toil.csv` — a rough estimate of the TOIL claimed per month,
  using the same sleeping/waking-hours logic as `calculate-toil.rb`.

Usage: `bundle exec ruby ooh-stats.rb`

**Environment Variables:**
* `OPSGENIE_API_KEY`: Your OpsGenie API key (required).
* `TOIL_SLEEPING_HOURS`: TOIL hours per de-duped acknowledged `sleepinghours` alert (default `0.0`).
* `TOIL_WAKING_HOURS`: TOIL hours per de-duped acknowledged `wakinghours` alert (default `0.0`).
* `YEARS_BACK`: How many years back to look (default `3`).

These can be set in a `.env` file in the same directory as the script.
```

- [ ] **Step 2: Verify**

Run: `grep -n "ooh-stats.rb" README.md`
Expected: matches the new heading line.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document ooh-stats.rb in README"
```

---

## Self-Review

**1. Spec coverage:**
- Daily counts incl. zeros → Task 2. ✓
- Monthly totals → Task 3. ✓
- Monthly TOIL total-only, sleeping/waking + 30-min de-dupe → Task 4. ✓
- OOH tag filter, month-chunked paginated fetch, 3-year range → Task 5. ✓
- Config env vars + missing-key guard + non-200 abort → Task 5. ✓
- Three named CSV output files → Task 5. ✓
- README section → Task 6. ✓
No gaps.

**2. Placeholder scan:** No TBD/TODO/vague steps; every code step shows full code. ✓

**3. Type consistency:** `month_windows` returns `[Date, Date]` pairs and is consumed identically in Tasks 3, 4, 5. `daily_counts`/`monthly_totals`/`monthly_toil` all take `(alerts, start_date, end_date, ...)` and return `Array` of 2-element rows, consumed uniformly by the CSV writers. Alert hash keys (`"createdAt"`, `"acknowledged"`, `"tags"`, `"report" => "acknowledgedBy"`) are consistent across tasks and match `calculate-toil.rb`. ✓
