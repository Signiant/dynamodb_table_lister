# dynamodb-table-lister

A docker container that runs a utility to list all dynamoDB tables in a region and dump the results to a file.  This is then read by the dynamodb-throughput-scaler container.  The intent is that the list of tables is dumped once per day.

