#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-01-04 20:49:58 +0000 (Sun, 04 Jan 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check Kafka brokers are fully working end-to-end by acting as both a producer and a consumer and checking that a unique generated message passes through the broker cluster successfully

Requires >= Kafka-0.8009 Perl library which added taint security mode support at my request for this program.

Written for Kafka 0.8 onwards due to incompatible changes between Kafka 0.7 and 0.8.

Tested on Kafka 0.8.1

Limitations (these all currently have tickets open to fix in the underlying API):

- checks only a single topic and partition due to limitation of the underlying API
- an invalid partition number will result in a non-intuitive error \": topic = '<topic>'\", as due to the underlying API
- required acks doesn't seem to have any negative effect when given an integer higher than the available brokers or replication factor
- first run if given a topic that doesn't already exist will cause the error \"Error: There are no known brokers: topic = '<topic>'\"
";

$VERSION = "0.1.1";

# Kafka lib requires Perl 5.10
use 5.010;
use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use Kafka qw/ $DEFAULT_MAX_BYTES $DEFAULT_MAX_NUMBER_OF_OFFSETS $RECEIVE_EARLIEST_OFFSETS $RECEIVE_LATEST_OFFSET $COMPRESSION_NONE $DEFAULT_MAX_BYTES $WAIT_WRITTEN_TO_LOCAL_LOG $BLOCK_UNTIL_IS_COMMITTED $RETRY_BACKOFF/;
use Kafka::Connection;
use Kafka::Consumer;
use Kafka::Producer;
use POSIX 'strftime';
use Scalar::Util 'blessed';
use Sys::Hostname;
#use Try::Tiny;
use Time::HiRes qw/time sleep/;

# Technically the default port is 6667 (and on Hortonworks sandbox) but it seems 9092 is more common so leaving it as 9092 for convenience
#set_port_default(6667);
set_port_default(9092);

env_creds("Kafka");

my $broker_list = "";
my $topic = "nagios";
my $list_topics;
my $partition = 0;
my $all_ISR = 0;
my $RequiredAcks = $WAIT_WRITTEN_TO_LOCAL_LOG;
my $send_max_retries    = 1;
my $receive_max_retries = 1;
my $retry_backoff = $RETRY_BACKOFF; # set to 200ms by Kafka library
my $ignore_invalid_msgs;
my $sleep = 0.5;

%options = (
    %hostoptions,
    "B|broker-list=s"           => [ \$broker_list,         "Comma separated list of brokers in form 'host:port' to try if broker specified by --host and --port is not the leader. Either host or broker list must be supplied at the minimum. If --host isn't specified then first broker in the list will be use for metadata retrieval" ],
    "T|topic=s"                 => [ \$topic,               "Kafka topic (default: nagios)" ],
    "p|partition=s"             => [ \$partition,           "Kafka partition number to check by pushing message through (default: 0)" ],
    "R|required-acks=s"         => [ \$RequiredAcks,        "Required Acks from Kafka replicas. Default is 'LOG' which requires ack from Kafka partition leader, alternatively 'ISR' requires commit on all In-Sync Replicas, or specifying any integer which will block until this number of In-Sync Replicas ack the message (causing timeout if you set it higher than the number of replicas you have). This doesn't seem to work at this time due to the underlying library" ],
    "I|ignore-invalid-messages" => [ \$ignore_invalid_msgs, "Ignore invalid messages, only try to find the unique message we produced in the stream. By default any invalid message since the offset when the program started could trigger a critical alert. Strong test of broker to leave this switch unset. Message we sent must be valid regardless, this is just to ignore some other producer problem" ],
    "send-max-retries=s"        => [ \$send_max_retries,    "Max number of send    retries for Kafka broker (default: 1, min: 1, max: 100)" ],
    "receive-max-retries=s"     => [ \$receive_max_retries, "Max number of receive retries for Kafka broker (default: 1, min: 1, max: 100)" ],
    "retry-backoff=s"           => [ \$retry_backoff,       "Retry backoff in milliseconds between retries  (default: 200, min: 1, max: 10000)" ],
    "sleep=s"                   => [ \$sleep,               "Sleep in seconds between producing and consuming from given topic (default: 0.5)" ],
    #"list-topics"               => [ \$list_topics,         "List Kafka topics from broker" ],
);
splice @usage_order, 6, 0, qw/broker-list topic partition required-acks ignore-invalid-messages send-max-retries receive-max-retries retry-backoff sleep list-topics/;

get_options();

my @broker_list;
if($broker_list){
    my ($host2, $port2);
    foreach(split(/\s*,\s*/, $broker_list)){
        ($host2, $port2) = split(/:/, $_);
        $host2 = validate_host($host2, "broker");
        $port2 = validate_port($port2, "broker");
        push(@broker_list, "$host2:$port2") unless grep { "$host2:$port2" eq $_ } @broker_list;
        unless($host){
            $host = $host2;
            $port = $port2;
        }
    }
    # add host and port if not already in there since this is used as the authoritative list of brokers to report on throughout the code
    unshift @broker_list, "$host:$port" unless grep { "$host:$port" eq $_ } @broker_list;
}
$host = validate_host($host);
$port = validate_port($port);
# XXX: currently no way to list topics in Perl's Kafka API
#unless($list_topics){
    $topic or usage "topic not defined";
    $topic =~ /^([A-Za-z0-9]+)$/ or usage "topic must be alphanumeric";
    $topic = $1;
#}
$partition = validate_int($partition, "partition", 0, 10000);
if($RequiredAcks eq "ISR"){
    $RequiredAcks = $BLOCK_UNTIL_IS_COMMITTED;
} elsif($RequiredAcks eq "LOCAL_LOG"){
    $RequiredAcks = $WAIT_WRITTEN_TO_LOCAL_LOG;
} else {
    isInt($RequiredAcks) or usage "--required-acks must be one of: ISR, LOG or an integer number >= 1";
}
vlog_options "required acks", $RequiredAcks;
# XXX: API Bug: doesn't allow zero retries as of 0.8009
$send_max_retries    = validate_int($send_max_retries,    "send-max-retries",    1, 100);
$receive_max_retries = validate_int($receive_max_retries, "receive-max-retries", 1, 100);
$retry_backoff       = validate_int($retry_backoff,       "retry-backoff",       1, 10000);
$sleep               = validate_float($sleep,             "sleep",               0.1, 10);

vlog2;
set_timeout();

$ENV{'PERL_KAFKA_DEBUG'} = 1 if $debug;

$status = "UNKNOWN";

my $broker_name = "";
if(@broker_list){
    if(scalar @broker_list > 1){
        $broker_name .= "s ";
    }
    if($verbose){
        $broker_name .= " at " if scalar @broker_list == 1;
        $broker_name .= join(",", @broker_list);
    }
} else {
    $broker_name = " at $host:$port" if $verbose;
}

my $epoch   = time;
my $tstamp  = strftime("%F %T", localtime($epoch));
my $random_string = random_alnum(20);
my $content = "This is a producer-consumer test message from HariSekhon:$progname:" . hostname . " at epoch $epoch ($tstamp) with random token: $random_string";

my ($connection, $consumer, $producer);
# XXX: don't call this until after fetching partition offsets as the API call $connection->is_server_alive() returns undef until that point even when broker is up
sub check_server_alive(){
    unless($connection->is_server_alive("$host:$port")){
        quit "CRITICAL", "Kafka broker" . ( $verbose ? " at $host:$port": "") . " is no longer alive!";
    }
}
try {
    vlog2 "connecting to Kafka broker$broker_name";
    # default timeouts are 1.5 secs
    $connection = Kafka::Connection->new( 
                                          #'broker'  => $broker_list, # XXX: TODO
                                          'host'        => $host,
                                          'port'        => $port,
                                          'broker_list' => \@broker_list,
                                          # default timeout $REQUEST_TIMEOUT = 1.5 secs
                                          #'timeout' => $timeout / 2,
                                          # XXX: API bug these two arguments don't allow zero retries
                                          'SEND_MAX_RETRIES'    => $send_max_retries,
                                          'RECEIVE_MAX_RETRIES' => $receive_max_retries,
                                          'RETRY_BACKOFF'       => $retry_backoff,
                                          'AutoCreateTopicsEnable' => 0,
                                        ) or quit "CRITICAL", "failed to connect to Kafka broker$broker_name! $!";
    vlog3 Dumper($connection) if $debug;

    # API BUG: this returns the list of supplied brokers, not ones actually detected and doesn't really add value
    #vlog2 "known servers: " . join(", ", $connection->get_known_servers());
    unless(@broker_list){
        if($connection->is_server_known("$host:$port")){
            vlog2 "server $host:$port is known to Kafka cluster";
        } else {
            quit "CRITICAL", "server '$host:$port' is not known to Kafka cluster";
        }
    }
    # XXX: $connection->is_server_alive() returns undef until partition fetch, don't call yet
    #check_server_alive() unless @broker_list;
    my $cluster_errors = $connection->cluster_errors();
    if(%$cluster_errors){
        quit "CRITICAL", "cluster errors detected: " . Dumper(%$cluster_errors);
    }

    vlog2 "connecting producer";
    $producer = Kafka::Producer->new(
                                      'Connection'    => $connection,
                                      'CorrelationId' => int(time),
                                      'ClientId'      => "Hari Sekhon $progname version $main::VERSION",
                                      # XXX: API BUG: this doesn't seem to take effect
                                      'RequiredAcks'  => $RequiredAcks,
                                      # default timeout $REQUEST_TIMEOUT = 1.5 secs
                                      #'Timeout'       => $timeout / 2,
                                    ) or quit "CRITICAL", "failed to connect producer to Kafka broker$broker_name! $!";
    vlog3 Dumper($producer) if $debug;

    vlog2 "connecting consumer\n";
    $consumer = Kafka::Consumer->new( Connection  => $connection ) or quit "CRITICAL", "failed to connect consumer to Kafka broker$broker_name! $!";
    vlog3 Dumper($consumer) if $debug;

    # When this partition number doesn't exist we get only this error thrown by the API
    # : topic = '$topic'
    vlog2 "retrieving current offsets\n";
    my $offsets = $consumer->offsets($topic, $partition, $RECEIVE_LATEST_OFFSET);
    if(@$offsets){
        vlog2 "received offsets for topic '$topic':\n";
        vlog2 "partition $partition => offset $$offsets[0]";
        # This always returns [offset, 0]
        #foreach(my $i=0; $i < scalar @$offsets; $i++){
        #    vlog2 "partition $i => offset $$offsets[$i]";
        #}
    } else {
        quit "CRITICAL", "no offsets retrieved!";
    }
    vlog2;
    check_server_alive() unless @broker_list;

    vlog2 "sending message to broker" . ( $verbose > 2 ? ":\n\n$content" : "" ) . "\n";
    my $response = $producer->send(
                                    $topic,
                                    $partition,
                                    $content,
                                    # rand(1), # key
                                    $COMPRESSION_NONE,
                                  ) or quit "CRITICAL", "failed to send message to Kafka broker$broker_name: $!";
    vlog3 Dumper($response) if $debug;
    check_server_alive() unless @broker_list;

    sleep $sleep;
    vlog2 "fetching messages";
    my $messages = $consumer->fetch($topic, $partition, $$offsets[0], $DEFAULT_MAX_BYTES) or quit "CRITICAL", "no messages fetched! $!";
    @$messages or quit "CRITICAL", "no messages returned by Kafka broker$broker_name! $!";
    check_server_alive() unless @broker_list;

    vlog2 "iterating on messages";
    my $found = 0;
    foreach my $message (@$messages){
        vlog3 Dumper($message);
        if(ref $message eq 'Kafka::Message'){
            if ($message->valid){
                if($message->payload eq $content){
                    $found++;
                    vlog2 "found matching message: " . $message->payload;
                }
            # XXX: consider doing $check_invalid to ignore checking all messages for validity since we're only interested 
            } elsif($ignore_invalid_msgs){
                vlog2 "ignoring invalid message at offset " . $message->offset . ", error: " . $message->error;
            } else {
                quit "CRITICAL", "error - message at offset " . $message->offset . " is not valid, error: " . $message->error . ". $nagios_plugins_support_msg_api";
            }
        } else {
            code_error "returned message is not a Kafka::Message object! $nagios_plugins_support_msg_api";
        }
    }
    vlog2;
    check_server_alive() unless @broker_list;

    if($found == 1){
        quit "OK", "message returned successfully by Kafka broker$broker_name";
    } elsif($found > 1){
        quit "WARNING", "message returned $found times for Kafka broker$broker_name!";
    } else {
        quit "CRITICAL", "message not returned by Kafka broker$broker_name!";
    }
};
catch {
    if ( blessed( $_ ) && $_->isa('Kafka::Exception') ) {
        quit "CRITICAL", 'Error: code: ' . $_->code . ', message: ' .  $_->message;
    } else {
        quit "CRITICAL", "Error: $_[0]";
    }
};

$msg .= " hit end of plugin";
quit $status, $msg;
