# dynamodb-table-lister

A docker container that runs a utility to list all dynamoDB tables in a region and dump the results to a file.
This is then read by the dynamodb-throughput-scaler container.

The intent is that the list of tables is dumped once per day.

## Config file
The app will readd the json config file and process any values in there.  If no keys are specified, instance role
credentials are used.  NOTE that values specified in variables OVERRIDE those specified in the config file

## Variables:

- DYNAMODB_REGION : The dynamoDB endpoint to connect to for monitoring tables
- FREQUENCY: How often to refresh the list of tables (in seconds).  Default 86400
- WRITEPERCENT: How much should we increase the WRITE provisioned throughput by (in percent)
- READPERCENT: How much should we increase the READ provisioned throughput by (in percent)

## Example Docker run

```
#!/bin/bash

docker run -d -e "DYNAMODB_REGION=dynamodb.us-east-1.amazonaws.com" \
              -e "FREQUENCY=86400" \
              -e "WRITEPERCENT=50" \
              -e "READPERCENT=50" \
			  --name dynamo-table-lister \
              signiant/dynamodb-table-lister
````