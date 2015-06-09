#!/usr/local/bin/ruby

%w[ getoptlong pp base64 openssl time yaml net/smtp ].each { |f| require f }

require 'rubygems'
require 'bundler/setup'

require 'aws-sdk-v1'
require 'fileutils'
require 'json'

# Turn off buffering
STDOUT.sync = true

CODE_OK = 0
CODE_WARNING = 1
CODE_CRITICAL = 2
CODE_UNKNOWN = 3

@start_time = Time.now()

@dynamo_db_endpoint = 'dynamodb.us-east-1.amazonaws.com'

@dynamo_regions = {};
@dynamo_regions["US East (Northern Virginia)"] =  "dynamodb.us-east-1.amazonaws.com"
@dynamo_regions["US West (Northern California)"] = "dynamodb.us-west-1.amazonaws.com"
@dynamo_regions["US West (Oregon)"] =  "dynamodb.us-west-2.amazonaws.com"
@dynamo_regions["EU (Ireland)"] =  "dynamodb.eu-west-1.amazonaws.com"
@dynamo_regions["EU (Frankfurt)"] =  "dynamodb.eu-central-1.amazonaws.com"
@dynamo_regions["Asia Pacific (Tokyo)"] =  "dynamodb.ap-northeast-1.amazonaws.com"
@dynamo_regions["Asia Pacific (Singapore)"] =  "dynamodb.ap-southeast-1.amazonaws.com"
@dynamo_regions["Asia Pacific (Sydney)"] =  "dynamodb.ap-southeast-2.amazonaws.com"
@dynamo_regions["South America (Sao Paulo)"] =  "dynamodb.sa-east-1.amazonaws.com"

# specify the options we accept and initialize and the option parser
@verbose = false
@frequency = 3600
@readIncreasePercent = 50
@writeIncreasePercent = 50
@create_all_table_file = false
ret = CODE_UNKNOWN 
use_rsa = false
$my_pid = Process.pid

@create_folder = "/tmp"
@config_files = {}

#####################################################
def create_config ( config_file )
	File.open("#{config_file}", 'w') { | f |
		f.puts "dynamodb:"
		f.close
	}
end

#####################################################
def append_to_config ( config_file, table_name, readIncrease, writeIncrease, global_indexes=nil )
	File.open("#{config_file}", 'a') { | f |
		f.puts "   #{table_name}:"
		f.puts "       #setReadCapacityUnitsTo: 5"
		f.puts "       #setWriteCapacityUnitsTo: 5"
		f.puts "       increaseReadCapacityUnitsByPercentage: #{readIncrease}"
		f.puts "       increaseWriteCapacityUnitsByPercentage: #{writeIncrease}"
		if global_indexes != nil
			f.puts "       global_indexes: "
		    global_indexes.each do | index |
			f.puts "           #{index[:index_name]}:"
			f.puts "               increaseReadCapacityUnitsByPercentage: 50"
			f.puts "               increaseWriteCapacityUnitsByPercentage: 50"
		    end
		end
		f.close
	}
end

#####################################################
def validate_region( regionIn, dynamo_regions)
	isValidRegion = false
	dynamo_regions.each do |key, name|
		if regionIn == name
			isValidRegion = true
		end
	end
    return isValidRegion
end

#####################################################
def save_table( table_name_prefix, table_name, readIncrease, writeIncrease)

	global_indexes = nil
	if table_name_prefix.nil?
		split_name = table_name.split("_")
		table_name_prefix = split_name[0]
	end

	dyn_resp = @dynamoApiClient.describe_table( options={:table_name=>table_name})

	pp dyn_resp if @verbose == true
	if dyn_resp.include?(:table)

	    if dyn_resp[:table].include?(:global_secondary_indexes)
		global_indexes = dyn_resp[:table][:global_secondary_indexes]
	    end
	end
	config_file = "#{@create_folder}/#{table_name_prefix.upcase}.yaml"
	if @config_files.has_key?(config_file) == false
		create_config(config_file)
		@config_files[config_file] = true
	end
	append_to_config( config_file, table_name, readIncrease, writeIncrease, global_indexes )
	if @create_all_table_file == true
		config_file = "#{@create_folder}/all_tables.yaml"
		if @config_files.has_key?(config_file) == false
			create_config(config_file)
			@config_files[config_file] = true
		end
		append_to_config( config_file, table_name, readIncrease, writeIncrease, global_indexes )
	end
end

#####################################################
def display_menu
    puts "Usage: #{$0} [-v]"
    puts "  --help, -h:                                         This Help"
    puts "  --verbose, -v:                                      Enable verbose mode"
    puts "  --list_regions, -l:                                 list the amazon endpoints"
    puts "  --output_dir <directoryName>, -o <directoryName>:   Path to write yaml configs"
	puts "  --config_file <json_file>, -n <json_file>:          Path to a json file containing cmd line overrides"
    puts "  --table_prefix <table_name>, -t <table_name>:       Optional table prefix to update, otherwise all tables saved"
    puts "  --region <aws region>, -r <aws region>:             amazon region (endpoint) default:#{@dynamo_db_endpoint}"
	puts "  --frequency <seconds>, -q <seconds>:                Generate the table list every N seconds"

    exit
end

#####################################################
def display_regions
        puts "Amazon DynamoDB Regions:"

        @dynamo_regions.each do |key, name|
            puts "Location '#{key}' Region '#{name}'"
        end
        exit
end

#####################################################
##### main
#####################################################
opts = GetoptLong.new

# add options
opts.set_options(
        [ "--help", "-h", GetoptLong::NO_ARGUMENT ], \
        [ "--verbose", "-v", GetoptLong::NO_ARGUMENT ], \
        [ "--list_regions", "-l", GetoptLong::NO_ARGUMENT ], \
        [ "--create_all_table_file", "-c", GetoptLong::NO_ARGUMENT ], \
        [ "--table_prefix", "-t", GetoptLong::REQUIRED_ARGUMENT ], \
        [ "--output_dir", "-o", GetoptLong::REQUIRED_ARGUMENT ], \
		[ "--config_file", "-n", GetoptLong::REQUIRED_ARGUMENT ], \
        [ "--region", "-r", GetoptLong::REQUIRED_ARGUMENT ], \
		[ "--frequency", "-q", GetoptLong::REQUIRED_ARGUMENT ]
      )

@cmdline_table_prefix = nil

# parse options
begin
	opts.each { |opt, arg|
	  case opt
	    when '--config_file'
		  # read the json config file
		  jsonFile = File.read(arg)
		  config_hash = JSON.parse(jsonFile)
		  @frequency = config_hash['frequency']
		  @verbose = config_hash['verbose']
		  @create_folder = config_hash['outputDir']
		  @cmdline_table_prefix = config_hash['tablePrefix']
		  @readIncreasePercent = config_hash['readIncreasePercent']
		  @writeIncreasePercent = config_hash['writeIncreasePercent']
		  @create_all_table_file = config_hash['createAllTableFile']
		  @secret_access_key = config_hash['secret_access_key']
		  @access_key_id = config_hash['access_key_id']
		  if validate_region( config_hash['region'],@dynamo_regions)
		      @dynamo_db_endpoint = config_hash['region']
		  else
		      puts "Error: Invalid region specified in the config file. Region must be one of..."
			  display_regions
		  end
	    when '--help'
	      display_menu
            when '--list_regions'
              display_regions
	    when '--verbose'
	      @verbose = true
	    when '--frequency'
	      @frequency = arg
		when '--create_all_table_file'
	      @create_all_table_file = true
	    when '--output_dir'
		  @create_folder = arg
	    when '--table_prefix'
		  @cmdline_table_prefix = arg
		when '--region'
		    if validate_region( arg,@dynamo_regions)
			    @dynamo_db_endpoint = arg
			else
			    puts "Error: Invalid region specified on the command line. Region must be one of..."
				display_regions
			end
	  end
	}
rescue => err
        #puts "#{err.class()}: #{err.message}"
        display_menu
end

# See if there are any environment specific overrides
if ENV['VERBOSE']
	myPuts "Verbose specified in environment - enabling verbose logging",true
	@verbose = true
end

if ENV['DYNAMODB_REGION']
	puts "DynamoDB region specified in environment - #{ENV['DYNAMODB_REGION']}"
	if validate_region( ENV['DYNAMODB_REGION'],@dynamo_regions)
		@dynamo_db_endpoint = ENV['DYNAMODB_REGION']
	else
		puts "Error: Invalid region specified in the environment. Region must be one of..."
		display_regions
	end
end

if ENV['FREQUENCY']
	puts "Polling frequency specified in environment - #{ENV['FREQUENCY']}"
	@frequency = Integer(ENV['FREQUENCY'])
end

if ENV['READPERCENT']
	puts "Read increase percentage specified in environment - #{ENV['READPERCENT']}"
	@readIncreasePercent = Integer(ENV['READPERCENT'])
end

if ENV['WRITEPERCENT']
	puts "Write increase percentage specified in environment - #{ENV['WRITEPERCENT']}"
	@writeIncreasePercent = Integer(ENV['WRITEPERCENT'])
end

puts "Creating Config Yaml files in directory #{@create_folder} every #{@frequency} seconds"

FileUtils.mkpath(@create_folder, :mode => 0777)

# DJN loop here
while true do
	# connect to Amazon
	d = DateTime.now
	puts "Process starts at #{d}"
	puts "connecting to AWS dynamoDB region #{@dynamo_db_endpoint}"
	
	useKeys = false
	if @access_key_id != nil && @access_key_id.length > 0
	  useKeys = true
	end
	
	begin
	  if useKeys
	    puts "Using AWS credentials in overrides file to connect to DynamoDB"
	    AWS.config(:dynamo_db => {:api_version => '2012-08-10'},
					:access_key_id => @access_key_id, 
					:secret_access_key => @secret_access_key,
					:dynamo_db_endpoint => @dynamo_db_endpoint)
	  else
	    puts "Using AWS role credentials to connect to DynamoDB"
	  	AWS.config(:dynamo_db => {:api_version => '2012-08-10'},
					:dynamo_db_endpoint => @dynamo_db_endpoint)
	  end
	  
	  @dynamoApiClient = AWS::DynamoDB::Client.new

	rescue Exception => e
	  puts "Error occurred while trying to connect to DynamoDB endpoint: #{e}\n"
	  exit CODE_CRITICAL
	end

	#########
	### load up the tables that need to be changed
	#########

	@is_truncated = true
	@exclusive_start_table_name = nil
	while @is_truncated == true
		begin
			if @exclusive_start_table_name.nil?
				tables = @dynamoApiClient.list_tables()
			else 
				tables = @dynamoApiClient.list_tables( options={:exclusive_start_table_name=>@exclusive_start_table_name})
			end
		rescue Exception => e
			puts "Error unable to start process with Amazon; aborting process"
			puts "Error List Tables:#{e}"
			exit CODE_CRITICAL
		end
		pp tables if @verbose == true
		tables[:table_names].each do |table_name|
			puts "table found #{table_name}" if @verbose == true
			if @cmdline_table_prefix.nil?
				puts "found table_name #{table_name}" if @verbose == true
				save_table( @cmdline_table_name_prefix, table_name, @readIncreasePercent, @writeIncreasePercent)
			elsif table_name.start_with?(@cmdline_table_prefix)
				puts "found table_name #{table_name}" if @verbose == true
				save_table( @cmdline_table_name_prefix, table_name, @readIncreasePercent, @writeIncreasePercent)
			end
		end
		if tables.include?(:last_evaluated_table_name)
			puts "-----------------------------------" if @verbose == true
			@exclusive_start_table_name = tables[:last_evaluated_table_name]
		else
			@is_truncated = false
		end
	end
	d = DateTime.now
	puts "Finished creating Yaml files at #{d}"
	e = d + Rational(@frequency,86400)
	puts "Will wake again at #{e}"
	sleep @frequency
end # infinite while loop

exit CODE_OK

