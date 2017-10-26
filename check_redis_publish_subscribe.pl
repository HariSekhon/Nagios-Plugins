#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-17 00:22:17 +0000 (Sun, 17 Nov 2013)
#  Continuation an idea from Q3/Q4 2012, inspired by other similar NoSQL plugins developed a few years earlier
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Redis server is up and working via publish/subscribe API calls

Checks:

1. Subscribes to a unique channel
2. Publishes to that same unique channel with a randomly generated and timestamped token
3. Waits for the channel to feed the message through for a given number of secs
4. Checks the message received is the same as the one published
5. compares each operation's time taken against the warning/critical thresholds if given

Tested on Redis 2.4, 2.6, 2.8, 3.0, 3.2, 4.0";

$VERSION = "0.6";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Redis;
use Redis;
use Sys::Hostname;
use Time::HiRes qw/time sleep/;

my $default_subscriber_wait = 0.001;
my $subscriber_wait = $default_subscriber_wait;
my ($subscriber_wait_min, $subscriber_wait_max) = (0.000001, 10);

%options = (
    %redis_options,
    "subscriber-wait=s"      => [ \$subscriber_wait,      "Let the subscriber wait this many secs to make sure it has received the message (default: $default_subscriber_wait, min: $subscriber_wait_min, max: $subscriber_wait_max)" ],
    "w|warning=s"        => [ \$warning,          "Warning  threshold in seconds for each publish/subscribe operation (use float for milliseconds)" ],
    "c|critical=s"       => [ \$critical,         "Critical threshold in seconds for each publish/subscribe operation (use float for milliseconds)" ],
);

@usage_order = qw/host port password subscriber-wait warning critical precision/;
get_options();

$host            = validate_host($host);
$port            = validate_port($port);
$password        = validate_password($password) if defined($password);
$subscriber_wait = validate_float($subscriber_wait, "subscriber-wait secs", $subscriber_wait_min, $subscriber_wait_max);
$precision       = validate_int($precision, "precision", 1, 20);
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );
vlog2;

my $epoch  = time;
my $random_string = random_alnum(20);
my $channel  = "HariSekhon:$progname:$host:$epoch:" . substr($random_string, 0, 10);
my $message  = "This is a publish-subscribe test message from " . hostname . ":HariSekhon:$progname to $host at epoch $epoch with random token: $random_string";
vlog_option "channel", $channel;
vlog_option "message", $message;
vlog2;
set_timeout();

$status = "OK";

my $redis_publisher;
my $redis_subscriber;
my $hostport;
# all the checks are done in connect_redis, will error out on failure
($redis_publisher, $hostport)  = connect_redis(host => $host, port => $port, password => $password);
($redis_subscriber, $hostport) = connect_redis(host => $host, port => $port, password => $password);

my $returned_message = "";
sub subscribe_callback(@){
    # subscribed_topic == psubscribe string
    my ($message, $topic, $subscribed_topic) = @_;
    my $err = "callback triggered but failed to receive ";
    quit "CRITICAL", "$err message. $nagios_plugins_support_msg"          unless $message;
    quit "CRITICAL", "$err topic. $nagios_plugins_support_msg"            unless $topic;
    quit "CRITICAL", "$err subscribed_topic. $nagios_plugins_support_msg" unless $subscribed_topic;
    ($topic eq $subscribed_topic) or code_error "redis API returned inconsistent topic vs subscribed_topic ('$topic' vs '$subscribed_topic')";
    ($topic eq $channel) or code_error "wrong topic returned to callback function, expected '$channel', got '$topic'";
    ($subscribed_topic eq $channel) or code_error "wrong subscribed_topic returned to callback function, expected '$channel', got '$subscribed_topic'";
    $returned_message = $message;
}

vlog2 "subscribing to channel on $hostport";
my $start_time   = time;
try {
    $redis_subscriber->subscribe(($channel), \&subscribe_callback);
};
catch_quit "failed to publish message to channel '$channel' to redis server $hostport";
my $subscribe_time = time - $start_time;
$subscribe_time    = sprintf("%0.${precision}f", $subscribe_time);

vlog2 "\npublishing to channel on $hostport";
$start_time         = time;
try {
    $redis_publisher->publish($channel, $message) || quit "CRITICAL", "failed to publish message to channel '$channel' on redis host $hostport";
};
catch_quit "failed to publish message to channel '$channel' on redis host $hostport";
my $publish_time       = time - $start_time;
$publish_time          = sprintf("%0.${precision}f", $publish_time);

plural $subscriber_wait;
my $wait_time;
vlog2;
if($returned_message){
    # This is never the case, must call wait_for_messages;
    code_error "message was found before calling redis_subscriber->wait_for_messages!!!";
    #vlog2 "message already returned, not waiting for $subscriber_wait sec$plural for subscriber-wait";
    #$wait_time = 0;
} else {
    vlog2 "waiting for $subscriber_wait sec$plural for message for subscribed channel";
    $start_time = time;
    while(1){
        try{
            $redis_subscriber->wait_for_messages(0.000001);
        };
        catch_quit "error waiting for messages for channel '$channel' on redis server $hostport";
        if($message or ((time - $start_time) >= $subscriber_wait)){
            last;
        }
    }
    $wait_time = time - $start_time;
    $wait_time    = sprintf("%0.${precision}f", $wait_time);
}

vlog2 "testing message content returned";
vlog3 "message returned: '$returned_message'";
plural $subscriber_wait;
unless($returned_message){
    quit "CRITICAL", "message was not returned from redis server $hostport within $subscriber_wait sec$plural";
}
if($message eq $returned_message){
    vlog3 "returned message matches message originally sent";
} else {
    quit "CRITICAL", "channel '$channel' returned wrong message '$returned_message', expected '$message' that was just written, INVESTIGATION REQUIRED";
}

vlog2 "\nclosing publisher and subscriber clients";
try {
    $redis_publisher->quit;
    $redis_subscriber->quit;
};

vlog2;
my $msg_perf = " |";
my $msg_thresholds = "s" . msg_perf_thresholds(1);
$msg_perf .= " publish_time=${publish_time}${msg_thresholds}";
$msg_perf .= " subscribe_time=${subscribe_time}${msg_thresholds}";
$msg_perf .= " wait_time=${wait_time}${msg_thresholds}";

$msg = "publish/subscribe message returned correctly, published in $publish_time secs, subscribed in $subscribe_time secs, $wait_time secs channel wait time on redis server $host" . ( $verbose ? ":$port" : "");

# TODO: capitalize the sections breaching the thresholds
#my ($status2, $msg);
#($status2, $msg) = check_thresholds($publish_time, 1);
#($status2, $msg) = check_thresholds($subscribe_time, 1);
#($status2, $msg) = check_thresholds($wait_time, 1);
check_thresholds($wait_time, 1);
check_thresholds($subscribe_time, 1);
check_thresholds($publish_time);

$msg .= $msg_perf;

quit $status, $msg;
