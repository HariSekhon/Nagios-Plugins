#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.admin.doc/doc/rest_access_cluster_mgt.html?lang=en

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Agents via the BigInsights Console REST API

Checks:

- stopped agents (includes dead) vs thresholds (default: w=0, c=1)
- operational agents vs running agents (warning if differ)
- outputs perfdata for graphing of running/operational/stopped/dead/live agents

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;

set_threshold_defaults(0, 1);

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $skip_operational_check;

%options = (
    %biginsights_options,
    "skip-operational-check"    =>  [ \$skip_operational_check, "Do not check operational agents vs running agents (only checks stopped agents vs thresholds)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, "skip-operational-check";

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds();
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

curl_biginsights "/ClusterStatus/cluster_summary.json", $user, $password;

my $monitoring;
isArray(get_field("items")) or quit "UNKNOWN", "'items' field is not an array as expected. $nagios_plugins_support_msg_api";
foreach my $item (@{$json->{"items"}}){
    my $id = get_field2($item, "id");
    if($id eq "monitoring"){
        $monitoring = $item;
    }
}
defined($monitoring) or quit "UNKNOWN", "couldn't find 'monitoring' item in json output returned by BigInsights Console. $nagios_plugins_support_msg_api";
foreach(qw/runningAgents stoppedAgents operationalAgents live dead/){
    isInt(get_field2($monitoring, $_)) or quit "UNKNOWN", "'$_' field was not an integer as expected (returned: " . $monitoring->{$_} . ")! $nagios_plugins_support_msg_api";
}
if($skip_operational_check){
    vlog2 "\nskipping operational vs running agents check" if $skip_operational_check;
} else {
    vlog2 "checking operational agents == running agents";
    my $non_operational_agents = $monitoring->{"runningAgents"} - $monitoring->{"operationalAgents"};
    if($non_operational_agents < 0){
        unknown;
        my $msg2 = "non-operational agents '$non_operational_agents' < 0 !!";
        vlog2 "\n** $msg2\n";
        $msg = "$msg2 $nagios_plugins_support_msg_api. $msg";
    } elsif($non_operational_agents != 0){
        warning;
        $msg = sprintf("%s non-operational agents detected. $msg", $non_operational_agents);
    }
}
foreach(qw/runningAgents stoppedAgents/){
    $msg .= sprintf("%s = %s, ", $_, $monitoring->{$_});
}
$msg =~ s/, $//;
vlog2 "checking stoppedAgents against thresholds";
check_thresholds($monitoring->{"stoppedAgents"});
$msg .= sprintf(", operationalAgents = %s, live = %s, dead = %s | runningAgents=%d stoppedAgents=%d", $monitoring->{"operationalAgents"}, $monitoring->{"live"}, $monitoring->{"dead"}, $monitoring->{"runningAgents"}, $monitoring->{"stoppedAgents"});
msg_perf_thresholds();
$msg .= sprintf(" operationalAgents=%d live=%d dead=%d", $monitoring->{"operationalAgents"}, $monitoring->{"live"}, $monitoring->{"dead"});

vlog2;
quit $status, $msg;
