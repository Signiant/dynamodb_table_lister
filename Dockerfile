FROM ruby:2.1-onbuild

RUN mkdir /dynamodb_table_defs
VOLUME /dynamodb_table_defs

CMD ["./dynamo_build_config.rb", "--config_file", "config.json"]