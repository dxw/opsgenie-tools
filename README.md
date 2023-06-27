# OpsGenie Tools

A collection of scripts to help with getting data from OpsGenie.

## Tools

### oncall-hours.rb

A script to output the number of hours that people have done on call for in
period we use for paying for our rota.

usage: `PAYMENT_RATE=10.00 OPSGENIE_API_KEY=yourkeyhere OPSGENIE_SCHEDULE_ID=youridhere OPSGENIE_ROTATION_ID=youridhere bundle exec oncall-hours.rb`

You can also set OPSGENIE_DATE to a date in the month you want to calculate for, otherwise it will use the current date.
These can all be set in a `.env` file in the same directory as the script as well

### oncall.rb

A script to output who is on call for the next 4 weeks.
