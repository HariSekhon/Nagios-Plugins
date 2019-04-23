#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-09-30 16:38:25 +0100 (Wed, 30 Sep 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

# http://mesos.apache.org/documentation/latest/monitoring/

our $DESCRIPTION = "Nagios Plugin to check Mesos metrics for either a Master or Slave via the Rest API

Outputs all metrics by default, or can specify one or more metrics.

May specify optional thresholds if fetching a single metric.

Tested on Mesos 0.23, 0.24, 0.25";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';

# list of metrics that are actually counters and should be output suffixed with 'c' for perfdata
my @metric_counters = qw(
    master/slave_registrations
    master/slave_removals
    master/slave_reregistrations
    master/slave_shutdowns_scheduled
    master/slave_shutdowns_cancelled
    master/slave_shutdowns_completed
    master/tasks_error
    master/tasks_failed
    master/tasks_finished
    master/tasks_killed
    master/tasks_lost
    master/invalid_executor_to_framework_messages
    master/invalid_framework_to_executor_messages
    master/invalid_status_update_acknowledgements
    master/invalid_status_updates
    master/dropped_messages
    master/messages_authenticate
    master/messages_deactivate_framework
    master/messages_exited_executor
    master/messages_framework_to_executor
    master/messages_kill_task
    master/messages_launch_tasks
    master/messages_reconcile_tasks
    master/messages_register_framework
    master/messages_register_slave
    master/messages_reregister_framework
    master/messages_reregister_slave
    master/messages_resource_request
    master/messages_revive_offers
    master/messages_status_udpate
    master/messages_status_update_acknowledgement
    master/messages_unregister_framework
    master/messages_unregister_slave
    master/valid_framework_to_executor_messages
    master/valid_status_update_acknowledgements
    master/valid_status_updates
    slave/executors_terminated
    slave/tasks_failed
    slave/tasks_finished
    slave/tasks_killed
    slave/tasks_lost
    slave/invalid_framework_messages
    slave/invalid_status_updates
    slave/valid_framework_messages
    slave/valid_status_updates
);

if($progname =~ /master/){
    set_port_default(5050);
    env_creds(["Mesos Master", "Mesos"], "Mesos Master");
    $DESCRIPTION =~ s/metrics for either a Master or Slave/Master metrics/;
} elsif($progname =~ /slave/){
    set_port_default(5051);
    env_creds(["Mesos Slave", "Mesos"], "Mesos Slave");
    $DESCRIPTION =~ s/metrics for either a Master or Slave/Slave metrics/;
} else {
    env_creds("Mesos");
}

my $metrics;
my @metrics;
my $short;
my $include_framework;

%options = (
    %hostoptions,
    "m|metrics=s" => [ \$metrics, "Metric(s) to fetch, comma separated (defaults to fetching all metrics)" ],
    "f|include-framework" => [ \$include_framework, "Include framework related metrics" ],
    # can't use short option since event_queue_dispatches appears under both master/ and allocator/
    #"s|short"     => [ \$short, "Use short metric names by stripping the leading master/ or slave/ prefixes" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/metrics short/;

get_options();

$host = validate_host($host);
$port = validate_port($port);

if(defined($metrics)){
    foreach(split(",", $metrics)){
        $_ = trim($_);
        /^\s*([\w\/_]+)\s*$/ or usage "invalid metric '$_' given, must be alphanumeric with underscores and slashes";
        push(@metrics, $1);
    }
    @metrics or usage "no valid metrics given";
    @metrics = uniq_array @metrics;
    vlog_option "metrics", "[ " . join(" ", @metrics) . " ]";
}
my $num_metrics = scalar @metrics;
if($num_metrics != 1 and ( defined($warning) or defined($critical) ) ){
    usage "thresholds may only be given when specifying a single metric";
}

validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

$json = curl_json "http://$host:$port/metrics/snapshot";
vlog3 Dumper($json);

$msg = "Mesos metrics:";
my $msg2;

my %metrics;
foreach(sort keys %{$json}){
    my $key = $_;
    if (!$include_framework and $key =~ /^master\/frameworks\//) {
        next
    }
    #$key =~ s/^\w+\/// if($short);
    defined($metrics{$key}) and quit "UNKNOWN", "duplicate metric '$key' found! $nagios_plugins_support_msg_api";
    $metrics{$key} = $json->{$_};
    isScientific($metrics{$key}) or isFloat($metrics{$key}) or quit "UNKNOWN", "metric '$key' = '$metrics{$key}' - is not a float! $nagios_plugins_support_msg_api";
    $metrics{$key} = sprintf("%.2f", $metrics{$key}) if $metrics{$key} =~ /\./;
    vlog2 "$key => $metrics{$key}";
}
vlog2;

%metrics or quit "UNKNOWN", "no metrics found. $nagios_plugins_support_msg_api";

sub msg_metric($){
    my $key = shift;
    unless(defined($metrics{$key})){
        quit "UNKNOWN", "metric not found '$key'";
    }
    $msg  .= " $key=$metrics{$key}";
    $msg2 .= " '$key'=$metrics{$key}";
    if(grep { $key eq $_ } @metric_counters){
        $msg2 .= "c";
    }
}

if(@metrics){
    if($num_metrics == 1){
        msg_metric($metrics[0]);
        check_thresholds($metrics{$metrics[0]});
    } else {
        foreach my $key (@metrics){
            msg_metric($key);
        }
    }
} else {
    foreach my $key (sort keys %metrics){
        msg_metric($key);
    }
}

$msg .= " |" . $msg2;
msg_perf_thresholds() if $num_metrics == 1;

vlog2;
quit $status, $msg;
