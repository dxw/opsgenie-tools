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

## License

MIT License
