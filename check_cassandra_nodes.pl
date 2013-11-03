#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-13 19:32:32 +0100 (Sun, 13 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

# TODO: check if I can rewrite a version of this via API

$DESCRIPTION = "Nagios Plugin to check the number of available cassandra nodes and raise warning/critical on down nodes.

Uses nodetool's status command to determine how many downed nodes there are to compare against the warning/critical thresholds, also returns perfdata for graphing the node counts and states.

Can specify a remote host and port otherwise it checks the local node's stats (for calling over NRPE on each Cassandra node)

Written and tested against Cassandra 2.0, DataStax Community Edition";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::Cassandra;

my $default_warning  = 0;
my $default_critical = 1;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    %nodetool_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold max (inclusive. Default: $default_warning)"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold max (inclusive. Default: $default_critical)" ],
);

@usage_order = qw/nodetool host port user password warning critical/;
get_options();

$nodetool = validate_nodetool($nodetool);
$host     = validate_host($host) if defined($host);
$port     = validate_port($port) if defined($port);
$user     = validate_user($user) if defined($user);
$password = validate_password($password) if defined($password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}status";

vlog2 "fetching cluster nodes information";
if(defined($host)){
    validate_resolvable($host);
}
my @output = cmd($cmd);
my $alive_nodes   = 0;
my $dead_nodes    = 0;
my $normal_nodes  = 0;
my $leaving_nodes = 0;
my $joining_nodes = 0;
my $moving_nodes  = 0;
foreach(@output){
    if(/^Datacenter/i or
       /^==========/ or
       /^Status=Up\/Down/i or
       /\|\/\s+State=Normal\/Leaving\/Joining\/Moving/i or
       /^--\s+Address/i){
       next;
    }
    # Don't know what remote JMX auth failure looks like yet so will go critical on any user/password related message returned assuming that's an auth failure
    if($_ =~ $nodetool_errors_regex){
        quit "CRITICAL", $_;
    }
    if(/^U[NLJM]\s+($host_regex)/){
        $alive_nodes++;
        if(/^.N/){
            $normal_nodes++;
        } elsif(/^.L/){
            $leaving_nodes++;
        } elsif(/^.J/){
            $joining_nodes++;
        } elsif(/^.M/){
            $moving_nodes++;
        } else {
            quit "UNKNOWN", "unrecognized second column for node status, $nagios_plugins_support_msg";
        }
    } elsif(/^D/){
        $dead_nodes++;
    } else {
        quit "UNKNOWN", "unrecognized line in output from nodetool, intentionally failing check for conservative monitoring. $nagios_plugins_support_msg";
    }
}

vlog2 "checking node counts";
unless($alive_nodes == ($normal_nodes + $leaving_nodes + $joining_nodes + $moving_nodes)){
    quit "UNKNOWN", "alive node count vs (normal/leaving/joining/moving) nodes are not equal, investigation required";
}

$msg = "$alive_nodes nodes up, $dead_nodes dead";
check_thresholds($dead_nodes);
$msg .= ", node states: $normal_nodes normal, $leaving_nodes leaving, $joining_nodes joining, $moving_nodes moving | alive_nodes=$alive_nodes dead_nodes=$dead_nodes";
msg_perf_thresholds();
$msg .= " normal_nodes=$normal_nodes leaving_nodes=$leaving_nodes joining_nodes=$joining_nodes moving_nodes=$moving_nodes";

vlog2;
quit $status, $msg;
