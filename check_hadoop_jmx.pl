#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-11 12:59:27 +0000 (Mon, 11 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

our $DESCRIPTION = "Nagios Plugin to parse metrics from a given Hadoop daemon's /jmx page

Specify ports depending on which daemon you're trying to get JMX from: HDFS NameNode = 50070 / DataNode = 50075 (1022 if Kerberized), HBase Master = 16010 / RegionServer = 16030 (60010 or 60301 on older HBase versions <= 0.96)

Make sure you specify --mbean in prod, leave it out with --all-metrics and -vv only for exploring what is available. Nagios has a char limit and will truncate the output, and the perfdata at the end would be lost.

See metrics documentation for detailed description of important metrics to query:

https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/Metrics.html
https://hbase.apache.org/metrics.html
https://hbase.apache.org/book.html#hbase_metrics

Tested on Hadoop NameNode & DataNode and HBase Master & RegionServer on:

Hortonworks HDP 2.2 / 2.3
Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8
Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3
";

$VERSION = "0.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple qw/get $ua/;

my $bean;
my $list_beans;
my $metrics;
my $all_metrics;
my $expected;

if($progname =~ /namenode/){
    set_port_default(50070);
    $DESCRIPTION =~ s/\nSpecify port.*\n//;
    env_creds(["HADOOP_NAMENODE", "NAMENODE", "HADOOP"], "Hadoop NameNode");
} elsif($progname =~ /datanode/){
    set_port_default(50075);
    $DESCRIPTION =~ s/\nSpecify port.*\n//;
    env_creds(["HADOOP_DATANODE", "DATANODE", "HADOOP"], "Hadoop DataNode");
} elsif($progname =~ /hbase_master/){
    set_port_default(60010);
    $DESCRIPTION =~ s/\nSpecify port.*\n//;
    env_creds(["HBASE_MASTER", "HBASE"], "HBase Master");
} elsif($progname =~ /hbase_regionserver/){
    set_port_default(60030);
    $DESCRIPTION =~ s/\nSpecify port.*\n//;
    env_creds(["HBASE_REGIONSERVER", "HBASE"], "HBase RegionServer");
} else {
    env_creds("Hadoop");
}

%options = (
    %hostoptions,
    "b|bean=s"      => [ \$bean,         "Bean to check (see --list-beans)" ],
    "m|metrics=s"   => [ \$metrics,      "Metric(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single metrics is given" ],
    "a|all-metrics" => [ \$all_metrics,  "Grab all metrics. Useful if you don't know what to monitor yet or just want to graph everything" ],
    "e|expected=s"  => [ \$expected,     "Expected string match when specifying a single field to check. Use this to check non-float fields such as settings eg. -b Hadoop:service=NameNode,name=NameNodeStatus -m State -e active" ],
    "list-beans"    => [ \$list_beans,   "List all beans returned by HBase jmx page" ],
    %thresholdoptions,
);

@usage_order = qw/host port bean metrics all-metrics warning critical expected list-beans/;
get_options();

$host   = validate_host($host);
$host   = validate_resolvable($host);
$port   = validate_port($port);
$bean   = validate_java_bean($bean) if defined($bean);
my $url = "http://$host:$port/jmx";
my %stats;
my @stats;
unless($list_beans){
    if($all_metrics){
        defined($metrics) and usage "cannot specify --all-metrics and specific --metrics at the same time!";
    } else {
        defined($metrics) or usage "no metrics specified";
        foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
            $metric =~ /^[A-Za-z]+[\w.]*[A-Za-z]+$/i or usage "invalid metric '$metric' given, must be alphanumeric, may contain underscores and dots in middle";
            grep(/^$metric$/, @stats) or push(@stats, $metric);
        }
        @stats or usage "no valid metrics specified";
        @stats = uniq_array @stats;
        defined($bean) or usage "--bean must be defined if specifying --metrics";
    }
    validate_thresholds();
}
if(defined($expected)){
    scalar(@stats) == 1 or usage "must specify a single --metric if specifying --expected";
}

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

# ============================================================================ #

my $content = curl_json $url, "Hadoop daemon $host:$port";

my @beans = get_field_array("beans");

sub check_stats_parsed(){
    if($all_metrics){
        if(scalar keys %stats == 0){
            quit "UNKNOWN", "no stats collected from /metrics page (daemon recently started?)";
        }
        foreach(sort keys %stats){
            vlog2 "jmx $_ = $stats{$_}";
        }
    } else {
        foreach(@stats){
            unless(defined($stats{$_})){
                vlog2;
                quit "UNKNOWN", "failed to find $_ in output from '$host:$port'";
            }
            vlog2 "stats $_ = $stats{$_}";
        }
    }
    vlog2;
}

sub get_bean($){
    my $bean = shift;
    #my @beans = get_field_hash("beans");
    foreach(@beans){
        isHash($_) or quit "UNKNOWN", "invalid bean found, not a hash! $nagios_plugins_support_msg_api";
        if(get_field2($_, "name") eq $bean){
            return $_;
        }
    }
    quit "UNKNOWN", "failed to find bean with name '$bean'. Did you specify a correct bean name? See --list-beans to see available beans. If you're sure you specified a correct bean then $nagios_plugins_support_msg_api";
}

# for prototype checking
sub recurse_stats($$);

sub recurse_stats($$){
    my $key = shift;
    my $val = shift;
    defined($key) or code_error "key not defined when calling recurse_stats()";
    #defined($val) or code_error "val not defined when calling recurse_stats()";
    # turns out some JMX settings are genuinely null, capture this instead of raising an error
    if(not defined($val)){
        recurse_stats($key, "null");
        return;
    }
    if(isHash($val)){
        $key .= "." if $key;
        foreach(sort keys %{$val}){
            # special exception since plugins don't contain stats
            next if "$key$_" eq "nodes.plugins";
            recurse_stats("$key$_", ${$val}{$_});
        }
    } elsif(isArray($val)){
        $key .= "." if $key;
        foreach(my $i=0; $i < scalar @{$val}; $i++){
            recurse_stats("$key$i", $$val[$i]);
        }
    } else {
        return if $key eq "name" or $key eq "Valid" or $key =~ /AllThreadIds/;
        # save regardless, filter at end, this gives ability to check --expected against non-floats
        #if(isFloat($val)){
            defined($stats{$key}) and code_error "duplicate stat $key detected, must disambiguate";
            $stats{$key} = $val;
        #}
    }
}

sub parse_stats(){
    my @beans2 = @beans;
    my $bean_ref;
    if(defined($bean)){
        $bean_ref = get_bean($bean);
        @beans2 = ( $bean_ref );
    }
    if($all_metrics){
        foreach my $bean_ref (@beans2){
            my $base_name = "";
            unless(defined($bean)){
                $base_name = "[" . get_field2($bean_ref, "name") . "]";
            }
            recurse_stats($base_name, $bean_ref);
        }
    } elsif(@stats){
        $bean_ref or code_error "bean not defined";
        foreach(@stats){
            recurse_stats($_, get_field2($bean_ref, $_));
        }
    } else {
        quit "UNKNOWN", "metric to collect not specified";
    }
    check_stats_parsed();
}

# ============================================================================ #

if($list_beans){
    print "JMX Beans:\n\n";
    # easier to read
    my @names;
    foreach my $bean (@beans){
        isHash($bean) or quit "UNKNOWN", "non-hash bean detected. $nagios_plugins_support_msg_api";
        push(@names, get_field2($bean, "name"));
    }
    @names = sort_insensitive @names;
    print join("\n", @names) . "\n";
    exit $ERRORS{"UNKNOWN"};
}

vlog2 "parsing JMX from '$host:$port'\n";
parse_stats();

$msg = "";
if($bean){
    $msg .= "$bean: ";
}
if($all_metrics){
    foreach(sort keys %stats){
        $msg .= "$_=$stats{$_}, ";
    }
} else {
    foreach(@stats){
        $msg .= "$_=$stats{$_}, ";
    }
}
$msg =~ s/, $//;
if($all_metrics){
    $msg .= "| ";
    foreach(sort keys %stats){
        if(isFloat($stats{$_})){
            $msg .= "'$_'=$stats{$_} ";
        }
    }
} elsif(!$all_metrics and scalar @stats == 1){
    $msg =~ s/ $//;
    check_thresholds($stats{$stats[0]}) if isFloat($stats{$stats[0]});
    if($expected){
        unless($stats{$stats[0]} eq $expected){
            critical;
            $msg .= " (expected '$expected')";
        }
    }
    if(isFloat($stats{$stats[0]})){
        $msg .= " | '$stats[0]'=$stats{$stats[0]}";
    }
    msg_perf_thresholds();
} else {
    $msg .= "| ";
    foreach(sort keys %stats){
        if(isFloat($stats{$_})){
            $msg .= "'$_'=$stats{$_} ";
        }
    }
}

quit $status, $msg;
