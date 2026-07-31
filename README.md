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

A script to tag untagged alerts with a business unit tag. It can automatically tag alerts by matching client names in the alert message to a business unit.

**Environment Variables:**
* `OPSGENIE_API_KEY`: Your OpsGenie API key.
* `TAGS_TO_EXCLUDE`: A comma-separated list of tags to identify business units (e.g., `bu1,bu2`). Alerts with these tags will be excluded from the search.
* `CLIENT_TO_BU_MAPPING`: A JSON string that maps client names to business unit tags (e.g., `'{"clientA": "bu1", "clientB": "bu2"}'`). If a client name is found in an alert's message, the corresponding business unit tag will be added automatically.

If an alert message does not contain any of the specified client names, the script will fall back to prompting you to choose a tag to add.

### client_tags.rb

A script to tag alerts that have no `client_*` tag with a client tag. It can automatically tag alerts by matching strings in the alert message to a client tag, and takes an optional argument for how many days back to search (default 30), e.g. `bundle exec client_tags.rb 90`.

**Environment Variables:**
* `OPSGENIE_API_KEY`: Your OpsGenie API key.
* `CLIENT_TAG_MAPPING`: A JSON string that maps strings found in an alert message to client tags (e.g., `'{"dalmatian": "client_dalmatian", "caselaw": "client_moj"}'`). If a matching string is found in an alert's message, the corresponding client tag will be added automatically.

If an alert message does not match any of the mapping keys, the script will fall back to prompting you to enter a client name (leave blank to skip).

## License

MIT License
