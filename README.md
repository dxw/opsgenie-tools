# OpsGenie Tools

A collection of scripts to help with getting data from OpsGenie.

## Tools

### oncall-hours.rb

A script to output the number of hours that people have done on call for in
period we use for paying for our rota.

usage: `PAYMENT_RATE=10.00 OPSGENIE_API_KEY=yourkeyhere OPSGENIE_SCHEDULE_ID=youridhere OPSGENIE_ROTATION_ID=youridhere,youroptionalsecondidhere bundle exec oncall-hours.rb`

You can also set OPSGENIE_DATE to a date in the month you want to calculate for, otherwise it will use the current date.
These can all be set in a `.env` file in the same directory as the script as well

### oncall.rb

A script to output who is on call for the next 4 weeks.

### calcualte-toil.rb

A script to calculate the TOIL owed to people due to OOH alerts they have
acknowledged. This gives a rough estimate of the TOIL owed so that the Line
manager can be told how much the person should have claimed for their week.
This currently underestimates for the first line person if the alert was escalated.

### next-oncall.rb

A script to work out when a given user is next on call for given schedule and
rotation. These are set as environment variables the same as for
oncall-hours.rb. It will output the date the user is next on call.

### schedules.rb

A script to output the schedules that are available in OpsGenie. This is useful
for finding the ID of a schedule to use in the other scripts. It can also output
the rotations and their ID for a given schedule.

### tag_business_unit.rb

A script to tag untagged alerts with a business unit tag. It automatically tags alerts by mapping the alert's `client_*` tag to a business unit.

**Environment Variables:**
* `OPSGENIE_API_KEY`: Your OpsGenie API key.
* `TAGS_TO_EXCLUDE`: A comma-separated list of tags to identify business units (e.g., `bu1,bu2`). Alerts with these tags will be excluded from the search.
* `CLIENT_TO_BU_MAPPING`: A JSON string that maps client tags to business unit tags (e.g., `'{"client_clientA": "bu1", "clientB": "bu2"}'`). The `client_` prefix is optional and keys are matched case-insensitively.
* `CLIENT_TAG_MAPPING`: Optional, the same mapping used by `client_tags.rb`. When an alert has no `client_*` tag, the alert message is matched against these keys to work out which client tag it should have had.

Matching order for each alert:

1. the alert's own `client_*` tag, looked up in `CLIENT_TO_BU_MAPPING`
2. a client tag derived from the alert message via `CLIENT_TAG_MAPPING`, looked up in `CLIENT_TO_BU_MAPPING`
3. a prompt to choose a tag (or skip)

At the end of the run it prints suggested `CLIENT_TO_BU_MAPPING` additions for anything you tagged by hand, along with the full merged value to paste into your `.env`, and lists any alerts you skipped. Alerts with no `client_*` tag at all should be tagged with `client_tags.rb` first.

### client_tags.rb

A script to tag alerts that have no `client_*` tag with a client tag. It can automatically tag alerts by matching strings in the alert message to a client tag, and takes an optional argument for how many days back to search (default 30), e.g. `bundle exec client_tags.rb 90`.

**Environment Variables:**
* `OPSGENIE_API_KEY`: Your OpsGenie API key.
* `CLIENT_TAG_MAPPING`: A JSON string that maps strings found in an alert message to client tags (e.g. `'{"dalmatian": "client_dalmatian", "caselaw": "client_moj"}'`). If a matching string is found in an alert's message, the corresponding client tag will be added automatically.

If an alert message does not match any of the mapping keys, the script will fall back to prompting you to enter a client name (leave blank to skip).

After tagging an alert by hand it offers strings from the message that could be used as a new `CLIENT_TAG_MAPPING` key: hostnames from any URL and hyphen separated segments of CloudWatch alarm names, with obvious noise (`prod`, `ecs`, `cpu`, `5xx` and so on) left out. You can also type your own or decline. Each candidate is checked against the client tagged alerts of the last two years and any that also match a different client's alerts are listed last, annotated with the tags they clash with.

Anything you accept applies for the rest of the run, so repeat alerts for the same client are tagged automatically. At the end it prints the additions and the full merged `CLIENT_TAG_MAPPING` value to paste into your `.env`, plus a list of any alerts you skipped.

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

## License

MIT License
