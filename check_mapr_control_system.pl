#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://doc.mapr.com/display/MapR/API+Reference

$DESCRIPTION = "Nagios Plugin to check MapR Control System information such as Service & Node health, MapR-FS Space Used %, Node count, Alarms, Failed Disks, Cluster Version & License, MapReduce statistics etc via the MCS REST API

See instead newer single purpose check_mapr_* plugins in the Advanced Nagios Plugins Collection as they offer better control and more features.

Tested on MapR M3 version 3.1.0.23703.GA";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;
use JSON 'decode_json';

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8443);
#set_threshold_defaults(80, 90);

env_creds("MAPR", "MapR Control System");

my $cluster;
my $node;

my $blacklist_users = 0;
my $check_version   = 0;
my $dashboard       = 0;
my $disk            = 0;
my $failed_disks    = 0;
my $heartbeat_lag   = 0;
my $license         = 0;
my $license_apps    = 0;
my $list_cldbs      = 0;
my $list_vips       = 0;
my $listcldbzks     = 0;
my $listzookeepers  = 0;
my $mapreduce_stats = 0;
my $node_alarms     = 0;
my $node_health     = 0;
my $node_count      = 0;
my $node_metrics    = 0;
my $space_usage     = 0;
my $schedule        = 0;
my $services        = 0;
my $ssl_port;
my $table_listrecent = 0;
my $volumes          = 0;

my $ssl_ca_path;
my $tls_noverify;

%options = (
    %hostoptions,
    %useroptions,
    %thresholdoptions,
    "C|cluster=s"      => [ \$cluster,          "Cluster Name as shown in MapR Control System (eg. \"my.cluster.com\")" ],
    "S|services"       => [ \$services,         "Check all services on a given node, requires --node" ],
    "N|node=s"         => [ \$node,             "Node to check, use in combination with other switches such as --services" ],
    "d|dashboard"      => [ \$dashboard,        "Dashboard info. Raises critical if any services are failed" ],
    "A|node-alarms"    => [ \$node_alarms,      "Nodes with alarms" ],
    "O|node-count"     => [ \$node_count,       "Node count" ],
    "T|node-health"    => [ \$node_health,      "Node health, requires --node" ],
    "F|failed-disks"   => [ \$failed_disks,     "Failed disks, optional --node / --cluster for node specific or cluster wide" ],
    "B|heartbeat"      => [ \$heartbeat_lag,    "Heartbeat lag in secs for a given --node. Use --warning/--critical thresholds" ],
    # XXX: not currently available via REST API as of 3.1
    # Update: MapR have said they probably won't implement this since they "don't use the metrics database to show these metrics anywhere"
    #"node-metrics"     => [ \$node_metrics,     "Node metrics" ],
    "M|mapreduce-stats" => [ \$mapreduce_stats,  "MapReduce stats for graphing, raises critical if blacklisted > 0" ],
    # renamed to --space-usage
    #"rlimit"           => [ \$rlimit,           "Rlimit (only disk is supported as of MCS 3.1 so this reports current usage and cluster size)" ],
    "U|space-usage"    => [ \$space_usage,      "Space usage, reports current usage and cluster size. Use --warning and --critical to set % used thresholds" ],
    "list-cldbs"       => [ \$list_cldbs,       "List CLDB nodes" ],
    "L|license"        => [ \$license,          "Show license, requires --cluster" ],
    "check-version"    => [ \$check_version,    "Check version of MapR software" ],
    "ssl-CA-path=s"    => [ \$ssl_ca_path,      "Path to CA certificate directory for validating SSL certificate" ],
    "ssl-noverify"     => [ \$tls_noverify,     "Do not verify SSL certificate from MapR Control System" ],
    # Not that interesting to expose
    #"list-cldb-zks"            => [ \$listcldbzks,         "List CLDB & ZooKeeper nodes" ],
    #"list-schedule"            => [ \$schedule,            "List schedule" ],
    #"list-recent-tables"       => [ \$table_listrecent,    "List recent tables" ],
    #"list-vips"                => [ \$list_vips,           "List VIPs" ],
    #"list-volumes"             => [ \$volumes,             "List volumes" ],
    #"disk"                     => [ \$disk,                "Disk list" ],
    # TODO: MCS Bug: crashes Admin UI with cldb=$node and cluster
    #"list-zookeepers"          => [ \$listzookeepers,      "List ZooKeeper nodes (requires CLDB --node)" ],
    # TODO: MCS Bug: Not implemented at of MCS 3.1
    #"list-blacklisted-users"   => [ \$blacklist_users,     "List blacklisted users" ],
);

@usage_order = qw/host port user password cluster dashboard services node space-usage node-alarms node-count node-health heartbeat failed-disks mapreduce-stats list-cldbs list-vips license check-version --ssl-CA-path --ssl-noverify warning critical/;

# TODO:
#
# Jobs running on cluster
#
# http://doc.mapr.com/display/MapR/job+table
#
# Tasks for a specific job
#
# http://doc.mapr.com/display/MapR/task+table

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password) if $password;

if($cluster){
    $cluster =~ /^([\w\.]+)$/ or usage "invalid cluster name given";
    $cluster = $1;
}

if($services + $dashboard + $node_alarms + $node_count + $node_health + $heartbeat_lag + $failed_disks + $mapreduce_stats + $list_cldbs + $license + $check_version + $space_usage > 1){
    usage "can only specify one check at a time";
}

my $ip = validate_resolvable($host);
vlog2 "resolved $host to $ip";
my $url_prefix = "https://$ip:$port";
my $url = "$url_prefix/rest";

# TODO: http://doc.mapr.com/display/MapR/node+metrics

# http://doc.mapr.com/display/MapR/node
#
# Node Health: 
#
# 0 = Healthy
# 1 = Needs attention
# 2 = Degraded
# 3 = Maintenance
# 4 = Critical
my %node_states = (
    0 => "Healthy",
    1 => "Needs attention",
    2 => "Degraded",
    3 => "Maintenance",
    4 => "Critical",
);

# http://doc.mapr.com/display/MapR/service+list
#
#    0 - NOT_CONFIGURED: the package for the service is not installed and/or the service is not configured (configure.sh has not run)
#    2 - RUNNING: the service is installed, has been started by the warden, and is currently executing
#    3 - STOPPED: the service is installed and configure.sh has run, but the service is currently not executing
#    5 - STAND_BY: the service is installed and is in standby mode, waiting to take over in case of failure of another instance (mainly used for JobTracker warm standby)
my %service_states = (
    0 => "not_configured",
    2 => "running",
    3 => "stopped",
    # state 4 is Failed, currently undocumented as of MapR 3.1, MapR guys said they will document this
    4 => "failed",
    5 => "standby",
);

if($services){
    $node = validate_host($node, "node");
    $url .= "/service/list?node=$node";
} elsif($dashboard or $check_version or $mapreduce_stats){
    $url .= "/dashboard/info";
# Not sure on the value of this
# } elsif($disk){
#     if($cluster){
#         $url .= "/disk/listall?cluster=$cluster";
#     } else {
#         $node = validate_host($node, "node");
#         $url .= "/disk/list?host=$node";
#     }
#     # TODO: system=0 MapR only, system=1 OS only disks, not specified == both
#     # XXX: http://doc.mapr.com/display/MapR/disk#disk-disk-fields
#     #
} elsif($license){
    $cluster or usage "--license requires --cluster";
    $url .= "/license/list?cluster=$cluster";
#} elsif($license_apps){
#    $cluster or usage "--license-apps requires --cluster";
#    $url .= "/license/apps?cluster=$cluster";
} elsif($node_count){
    $url .= "/node/list";
    $url .= "&cluster=$cluster" if $cluster;
} elsif($node_alarms){
    $url .= "/node/list?alarmednodes=1";
    $url .= "&cluster=$cluster" if $cluster;
    $critical = 0 unless (defined($warning) or defined($critical));
} elsif($node_health){
    $node or usage "must specify --node";
    $url .= "/node/list?columns=service,health";
    $url .= "&cluster=$cluster" if $cluster;
} elsif($failed_disks){
    $url .= "/node/list?columns=faileddisks";
    $url .= "&cluster=$cluster" if $cluster;
} elsif($heartbeat_lag){
    $node or usage "must specify --node";
    $url .= "/node/list?columns=fs-heartbeat";
} elsif($list_cldbs){
    $url .= "/node/listcldbs";
    $url .= "?cluster=$cluster" if $cluster;
} elsif($list_vips){
    $url .= "/virtualip/list";
# Don't need to list both at the same time
#} elsif($listcldbzks){
#    $url .= "/node/listcldbzks";
#    $url .= "?cluster=$cluster" if $cluster;
#
# MCS BUG: managed to crash the service 8443 so it's not even bound to port any more fiddling with these cluster and cldb combinations!
#} elsif($listzookeepers){
#    #$node or usage "--list-zookeepers requires CLDB --node";
#    $url .= "/node/listzookeepers";
#    $url .= "?cluster=$cluster" if $cluster;
#    # every time I send cldb=$node with cluster it crashes the admin UI
#    #$url .= "&cldb=$node";
#} elsif($schedule){
#    $url .= "/schedule/list";
#} elsif($table_listrecent){
#    $url .= "/table/listrecent";
#} elsif($volumes){
#    $url .= "/volume/list";
# 
# TODO: MCS Bug - not be implemented as an endpoint and results in a 404 Not Found response
#} elsif($blacklist_users){
#    $url .= "/blacklist/listusers";
} elsif($space_usage){
    $cluster or usage "--space-usage requires --cluster";
    $url .= "/rlimit/get?resource=disk&cluster=$cluster";
} else {
    usage "no check specified";
}

if(defined($tls_noverify)){
    $ua->ssl_opts( verify_hostname => 0 );
}
if(defined($ssl_ca_path)){
    $ssl_ca_path = validate_directory($ssl_ca_path, undef, "SSL CA directory", "no vlog");
    $ua->ssl_opts( SSL_ca_path => $ssl_ca_path );
}
vlog_options "SSL CA Path",  $ssl_ca_path  if defined($ssl_ca_path);
vlog_options "SSL noverify", $tls_noverify ? "true" : "false";
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

$ua->show_progress(1) if $debug;
vlog2 "querying $url";
my $req = HTTP::Request->new('GET', $url);
$req->authorization_basic($user, $password);
my $response = $ua->request($req);
my $content  = $response->content;
chomp $content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http code: " . $response->code;
vlog2 "message: " . $response->message . "\n";
if(!$response->is_success){
    my $err = "failed to query MapR Control System at '$url_prefix': " . $response->code . " " . $response->message;
    if($content =~ /"message"\s*:\s*"(.+)"/){
        $err .= ". Message returned by MapR Control System: $1";
    }
    if($response->code eq 401 and $response->message eq "Unauthorized"){
        $err .= ". Invalid --user/--password?";
    }
    if($response->code eq 404 and $blacklist_users){
        $err .= ". Blacklist users API endpoint is not implemented as of MCS 3.1. This has been confirmed with MapR, trying updating to a newer version of MCS";
    }
    if($response->message =~ /Can't verify SSL peers without knowing which Certificate Authorities to trust/){
        $err .= ". Do you need to use --ssl-CA-path or --ssl-noverify?";
    }
    quit "CRITICAL", $err;
}
unless($content){
    quit "CRITICAL", "blank content returned by MapR Control System at '$url_prefix'";
}

vlog2 "parsing output from MapR Control System\n";

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by MapR Control System at '$url_prefix'";
};

defined($json->{"status"}) or quit "UNKNOWN", "status field not found in output. $nagios_plugins_support_msg";
if($debug){
    use Data::Dumper;
    print Dumper($json);
    print "\n";
}
unless($json->{"status"} eq "OK"){
    my $err = "status=" . $json->{"status"} . " - ";
    if(defined($json->{"errors"})){
        foreach(@{$json->{"errors"}}){
            if(defined($_->{"desc"})){
                $err .= $_->{"desc"} . ".";
            }
        }
    }
    $err =~ s/\.$//;
    quit "CRITICAL", $err;
}
defined($json->{"total"}) or quit "UNKNOWN", "total field not defined. $nagios_plugins_support_msg";

defined($json->{"data"}) or quit "UNKNOWN", "data field not found in output. $nagios_plugins_support_msg";
isArray($json->{"data"}) or quit "UNKNOWN", "data field is not an array. $nagios_plugins_support_msg";

if($services){
    $msg = "services on node '$node' - ";
    my %node_services;
    foreach my $service (@{$json->{"data"}}){
        defined($service->{"name"})  or quit "UNKNOWN", "service name field not defined in list of services. $nagios_plugins_support_msg";
        defined($service->{"state"}) or quit "UNKNOWN", "service state field not defined in list of services. $nagios_plugins_support_msg";
        # this relies on state 0 (unconfigured not existing in %service_states in order to exclude it from the list
        if(grep { $service->{"state"} eq $_ } keys %service_states){
            $node_services{$service->{"name"}} = $service_states{$service->{"state"}};
        } else {
            $node_services{$service->{"name"}} = "unknown";
        }
    }
    if(scalar keys %node_services >= 1){
        foreach(sort keys %node_services){
            # depends on service state mapping above in %service_states
            if($node_services{$_} ne "running" and $node_services{$_} ne "standby" and $node_services{$_} ne "not_configured"){
                critical;
                $node_services{$_} = uc $node_services{$_};
            }
            $msg .= $_ . ":" . $node_services{$_} . ", ";
        }
        $msg =~ s/, $//;
    } else {
        quit "CRITICAL", "no services on node '$node'";
    }
} elsif($dashboard){
    foreach my $cluster (@{$json->{"data"}}){
        defined($cluster->{"cluster"}{"name"}) or quit "UNKNOWN", "didn't find cluster name in output, format may have changed. $nagios_plugins_support_msg";
        defined($cluster->{"utilization"}->{"memory"}->{"active"}) and defined($cluster->{"utilization"}->{"memory"}->{"total"}) or quit "UNKNOWN", "didn't find memory active/total in output, format may have changed. $nagios_plugins_support_msg";
        $msg = "cluster: " . $cluster->{"cluster"}{"name"} . " ";
        $msg .= sprintf("memory: %.2f%% active (%d/%d) ", $cluster->{"utilization"}->{"memory"}->{"active"} / $cluster->{"utilization"}->{"memory"}->{"total"} * 100, $cluster->{"utilization"}->{"memory"}->{"active"}, $cluster->{"utilization"}->{"memory"}->{"total"});
        $msg .= "services: ";
        foreach my $service (sort keys %{$cluster->{"services"}}){
            my $msg2 = "";
            foreach(qw/active standby stopped failed/){
                if(defined($cluster->{"services"}->{$service}->{$_}) and $cluster->{"services"}->{$service}->{$_}){
                    $msg2 .= ($_ eq "failed" ? "FAILED" : $_ ) . "=" . $cluster->{"services"}->{$service}->{$_} . " ";
                    critical if($_ eq "failed");
                }
            }
            $msg2 =~ s/ $//;
            $msg2 = "$service $msg2" if $msg2;
            $msg .= "$msg2, ";
        }
        $msg =~ s/, $//;
        defined($cluster->{"volumes"}->{"mounted"}->{"total"}) and defined($cluster->{"volumes"}->{"unmounted"}->{"total"}) or quit "UNKNOWN", "didn't find memory active/total in output, format may have changed. $nagios_plugins_support_msg";
        $msg .= sprintf(", volumes: mounted=%d unmounted=%d", $cluster->{"volumes"}->{"mounted"}->{"total"}, $cluster->{"volumes"}->{"unmounted"}->{"total"});
        $msg .= ", ";
    }
    $msg =~ s/, $//;
} elsif($mapreduce_stats){
    foreach my $cluster (@{$json->{"data"}}){
        defined($cluster->{"cluster"}{"name"}) or quit "UNKNOWN", "didn't find cluster name in output, format may have changed. $nagios_plugins_support_msg";
        defined($cluster->{"utilization"}->{"memory"}->{"active"}) and defined($cluster->{"utilization"}->{"memory"}->{"total"}) or quit "UNKNOWN", "didn't find memory active/total in output, format may have changed. $nagios_plugins_support_msg";
        $msg = "cluster: " . $cluster->{"cluster"}{"name"} . " ";
        $msg .= sprintf("memory: %.2f%% active (%d/%d) ", $cluster->{"utilization"}->{"memory"}->{"active"} / $cluster->{"utilization"}->{"memory"}->{"total"} * 100, $cluster->{"utilization"}->{"memory"}->{"active"}, $cluster->{"utilization"}->{"memory"}->{"total"});
        $msg .= "mapreduce: ";
        my $msg2;
        foreach my $stat (sort keys %{$cluster->{"mapreduce"}}){
            quit "UNKNOWN", "non-integer result returned for $stat" if(!isInt($cluster->{"mapreduce"}->{$stat}));
            $msg2 .= "$stat=" . $cluster->{"mapreduce"}->{$stat} . " ";
        }
        defined($cluster->{"mapreduce"}->{"blacklisted"}) or quit "UNKNOWN", "didn't find blacklisted in output, format may have changed. $nagios_plugins_support_msg";
        if($cluster->{"mapreduce"}->{"blacklisted"}){
            critical;
        }
        $msg .= $msg2;
        $msg =~ s/blacklisted/BLACKLISTED/ if($cluster->{"mapreduce"}->{"blacklisted"});
        $msg .= "| $msg2";
    }
} elsif($license){
    defined($json->{"data"}[0]{"description"})  or quit "UNKNOWN", "description field not defined. $nagios_plugins_support_msg";
    defined($json->{"data"}[0]{"maxnodes"})     or quit "UNKNOWN", "maxnodes field not defined. $nagios_plugins_support_msg";
    $msg = "license: " . $json->{"data"}[0]{"description"} . ", max nodes: " . $json->{"data"}[0]{"maxnodes"};
} elsif($check_version){
    foreach(@{$json->{"data"}}){
        defined($_->{"version"})         or quit "UNKNOWN", "version field not defined. $nagios_plugins_support_msg";
        defined($_->{"cluster"}{"name"}) or quit "UNKNOWN", "cluster name field not defined. $nagios_plugins_support_msg";
        $msg = "cluster '" . $_->{"cluster"}{"name"} . "' version " . $_->{"version"} . ", ";
    }
    $msg =~ s/, $//;
} elsif($node_count){
    plural $json->{"total"};
    $msg = $json->{"total"} . " node$plural found";
    check_thresholds($json->{"total"});
    $msg .= " | nodes=" . $json->{"total"};
    msg_perf_thresholds();
} elsif($node_alarms){
    my @nodes_with_alarms;
    quit "UNKNOWN", "no node data returned, did you specify the correct --cluster?" unless @{$json->{"data"}};
    foreach(@{$json->{"data"}}){
        push(@nodes_with_alarms, $_->{"hostname"});
    }
    if(@nodes_with_alarms){
        check_thresholds(scalar @nodes_with_alarms);
        plural @nodes_with_alarms;
        $msg = scalar @nodes_with_alarms . " node$plural with alarm$plural: " . join(", ", sort @nodes_with_alarms);
        $msg .= " | node_alarms=" . scalar @nodes_with_alarms;
        msg_perf_thresholds;
    } else {
        $msg = "no nodes with alarms";
    }
} elsif($node_health){
    my $node_health_status;
    quit "UNKNOWN", "no node data returned, did you specify the correct --cluster?" unless @{$json->{"data"}};
    foreach my $node_item (@{$json->{"data"}}){
        if($node_item->{"hostname"} eq $node){
            if(grep { $node_item->{"health"} eq $_ } keys %node_states){
                $node_health_status = $node_states{$node_item->{"health"}};
            } else {
                $node_health_status = "UNKNOWN (" . $node_item->{"health"} . ")";
            }
            last;
        }
    }
    defined($node_health_status) or quit "UNKNOWN", "failed to find health of node '$node' in MCS output, did you specify the correct node FQDN?";
    $msg = "node '$node' health '$node_health_status'";
    # Dependent on %node_states
    if($node_health_status eq "Healthy"){
        $status = "OK";
    } elsif(grep { $node_health_status eq $_ } split(",", "Degraded,Needs attention,Maintenance")){
        $status = "WARNING";
    } else {
        $status = "CRITICAL";
    }
} elsif($failed_disks){
    my $faileddisks;
    quit "UNKNOWN", "no node data returned, did you specify the correct --cluster?" unless @{$json->{"data"}};
    foreach my $node_item (@{$json->{"data"}}){
        if($node){
            if($node_item->{"hostname"} =~ /^$node(?:\..+)?$/i){
                if(defined($node_item->{"faileddisks"})){
                    $faileddisks = $node_item->{"faileddisks"} unless $faileddisks;
                }
            }
        } else {
            if(defined($node_item->{"faileddisks"})){
                $faileddisks = $node_item->{"faileddisks"} unless $faileddisks;
            }
        }
    }
    unless(defined($faileddisks)){
        quit "UNKNOWN", "didn't find failed disk information in MCS output. " . ( $node ? "Did you specify the correct node FQDN? " : "" ) . "MCS API may have changed. $nagios_plugins_support_msg";
    }
    if($faileddisks){
        critical;
        $msg = $faileddisks;
    } else {
        $msg = "no";
    }
    plural $faileddisks;
    $msg .= " failed disk$plural detected";
    $msg .= " on node '$node'" if $node;
} elsif($heartbeat_lag){
    my $fs_heartbeat;
    quit "UNKNOWN", "no node data returned, did you specify the correct --cluster?" unless @{$json->{"data"}};
    foreach my $node_item (@{$json->{"data"}}){
        if($node_item->{"hostname"} eq $node){
            if(defined($node_item->{"fs-heartbeat"})){
                $fs_heartbeat = $node_item->{"fs-heartbeat"} unless $fs_heartbeat;
            }
        }
    }
    unless(defined($fs_heartbeat)){
        quit "UNKNOWN", "didn't find node's heartbeat information in MCS output. Did you specify the correct node FQDN? Alternatively MCS API may have changed. $nagios_plugins_support_msg";
    }
    isFloat($fs_heartbeat) or quit "CRITICAL", "heartbeat returned was not a float: '$fs_heartbeat'";
    $msg .= "node '$node' heartbeat last detected $fs_heartbeat secs ago";
    check_thresholds($fs_heartbeat);
    $msg .= " | heartbeat_age=${fs_heartbeat}s";
    msg_perf_thresholds();
} elsif($list_cldbs){
    # This count seems wrong, it states 1 when listing 2 different nodes
    #plural $json->{"total"};
    #$msg = $json->{"total"} . " CLDB node$plural";
    $msg = "CLDB nodes";
    $msg .= " in cluster '$cluster'" if $cluster;
    my @cldb_nodes;
    foreach(@{$json->{"data"}}){
        push(@cldb_nodes, $_->{"CLDBs"});
    }
    $msg .= ": " . join(", ", sort @cldb_nodes);
} elsif($space_usage){
    # XXX: This shouldn't list more than 1 cluster otherwise output will look weird / doubled
    foreach my $cluster (@{$json->{"data"}}){
        foreach(qw/currentUsage limit clusterSize/){
            defined($cluster->{$_}) or quit "UNKNOWN", "didn't find $_ in output, format may have changed. $nagios_plugins_support_msg";
            $msg .= "$_=" . $cluster->{$_} . " ";
        }
    }
    my $pc_space_used = sprintf("%.2f", expand_units($json->{"data"}[0]->{"currentUsage"}) / expand_units($json->{"data"}[0]->{"clusterSize"}) * 100);
    $msg = "$pc_space_used% space used $msg";
    $msg =~ s/ $//;
    check_thresholds($pc_space_used);
    $msg .= " | '% space used'=$pc_space_used%";
    msg_perf_thresholds();
    $msg .= "0;100; currentUsage=" . expand_units($json->{"data"}[0]->{"currentUsage"}) . "b;" . expand_units($json->{"data"}[0]->{"limit"}) . ";" . expand_units($json->{"data"}[0]->{"clusterSize"});
    #$msg .= "| currentUsage=" . $json->{"data"}[0]->{"currentUsage"} . ";" . $json->{"data"}[0]->{"limit"} . ";" . $json->{"data"}[0]->{"clusterSize"};
} elsif($list_vips){
    $msg = sprintf("%d VIPs", $json->{"total"});
} else {
    code_error "caught late - no check specified";
}

quit $status, $msg;
