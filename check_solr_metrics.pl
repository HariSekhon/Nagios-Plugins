#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-16 15:21:43 +0000 (Mon, 16 Feb 2015)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Solr / SolrCloud metrics via Solr API

There are too many metrics to practically output at the same time so you must at the least specify a category and possibly a specifc metric --key to return. Use the --list-categories switch to find out what categories are available, and then see output of what keys are returned (the first part of the metric name before the final dot).

Additionally, can drill down to a specific --stat to collect from that metric.

Optional thresholds apply if specifying a single --stat.

Tested on SolrCloud 4.x";

# Some useful metrics to collect
#
# Number of docs
# Number of queries / queries per second
# Average response time
# Number of updates
# Cache hit ratios
# Replication status
# Synthetic queries

our $VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;
use URI::Escape;

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $category;
my $key;
my $list_categories;
my $list_keys;
my $stat;
my %stats;

%options = (
    %solroptions,
    "C|cat|category=s" => [ \$category,         "Category of statistics to return (required unless doing --list-categories)" ],
    "K|key=s"          => [ \$key,              "Specific metrics to fetch by key name (case sensitive, optional)" ],
    "s|stat=s"         => [ \$stat,             "Stat for given metric key, optional thresholds will apply to this if specified" ],
    "list-categories"  => [ \$list_categories,  "List metric categories and exit" ],
    "list-keys"        => [ \$list_keys,        "List metric keys for a given category and exit" ],
    %solroptions_context,
    %thresholdoptions,
);
@usage_order = qw/host port user password category key stat list-categories http-context/;

get_options();

$host     = validate_host($host);
$port     = validate_port($port);
unless($list_categories){
    $category = validate_alnum($category, "category");
    # Solr Categories are case sensitive uppercase otherwise nothing is returned
    $category = uc $category;
}
if(defined($key)){
    #$key = validate_alnum($key, "key");
    $key =~ /^(\w[\.\w\@\[\]\s-]+\w)$/ or usage "invalid key defined, must be alphanumeric with dots to separate mbean from metric key";
    $key = $1;
    #$stat = $2 if $2;
    validate_thresholds();
}
$stat = validate_alnum($stat, "stat") if defined($stat);
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $url = "$solr_admin/mbeans?stats=true";
unless($list_categories){
    $url .= "&cat=$category" if $category;
    unless($list_keys){
        $url .= "&key=" . uri_escape($key) if $key;
    }
}

$json = curl_solr $url;

my @mbeans = get_field_array("solr-mbeans");

if($list_categories){
    print "Solr Metric Categories:\n\n";
    foreach (my $i = 0; $i < scalar @mbeans; $i+=2){
        print $mbeans[$i] . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}
if($list_keys){
    print "Solr Metric keys for category '$category':\n\n";
    unless(isHash($mbeans[1]) and %{$mbeans[1]}){
        quit "UNKNOWN", "no metrics returned for category '$category', did you specify a correct category as listed by --list-categories?";
    }
    foreach (my $i = 1; $i < scalar @mbeans; $i+=2){
        isHash($mbeans[$i]) or quit "UNKNOWN", "mbean member $i is not a hashref, got '$mbeans[$i]'. $nagios_plugins_support_msg_api";
        foreach my $key (sort keys %{$mbeans[$i]}){
            print "$key\n";
        }
    }
    exit $ERRORS{"UNKNOWN"};
}

unless(isHash($mbeans[1]) and %{$mbeans[1]}){
    quit "UNKNOWN", "no metrics returned for category '$category'" . ( defined($key) ? " key '$key'" : "" ). ", did you specify a correct category as listed by --list-categories and correct key as listed by --list-keys?";
}

# This construct is the more general purpose left over from parsing all the metric categories, still viable now using only a single category
foreach (my $i = 1; $i < scalar @mbeans; $i+=2){
    isHash($mbeans[$i]) or quit "UNKNOWN", "mbean member $i is not a hashref, got '$mbeans[$i]'. $nagios_plugins_support_msg_api";
    #print "i $i => " . Dumper(%{$mbeans[$i]});
    foreach my $key (keys %{$mbeans[$i]}){
        my $key_dot = $key;
        $key_dot =~ s/\./\\./g;
        #print "key $key => " . Dumper($mbeans[$i]{$key});
        my %keys2 = get_field2_hash($mbeans[$i], "$key_dot.stats", 1);
        if(%keys2){
            foreach (sort keys %keys2){
                if($stat){
                    next unless $_ eq $stat;
                }
                my $value = $keys2{$_};
                if(defined($value) and isFloat($value)){
                    if(defined($stats{"${key}.$_"})){
                        code_error "duplicate key '${key}.$_' detected";
                    }
                    vlog2 "$key => $_  = $value";
                    $stats{$key}{$_} = $value;
                } elsif($stat and not isFloat($value)){
                    quit "UNKNOWN", "stat '$stat' for metric '$key' is not numeric, cannot be a statistic. Please specify a numeric statistic field instead, omit --stat to see the full list of valid metric stats";
                }
            }
        }
    }
}

unless(%stats){
    if($stat){
        quit "UNKNOWN", "stat '$stat' not found for key '$key', did you specify the correct stat name? Try omitting it to see what stats are returned for this category";
    } else {
        quit "UNKNOWN", "no stats collected. Stats may be null or $nagios_plugins_support_msg_api"
    }
}

$msg .= "Solr " . lc $category . " ";
my $msg2;
my $num_stats = 0;
foreach(keys %stats){
    $num_stats += scalar keys $stats{$_};
}
vlog2 "$num_stats stats collected";
foreach my $key (sort keys %stats){
    $msg .= "$key";
    foreach(sort keys $stats{$key}){
        #print "$_=$stats{$_}\n";
        $msg  .= " $_=$stats{$key}{$_}";
        $msg2 .= " '${key} => $_'=$stats{$key}{$_}";
        if($num_stats == 1){
            check_thresholds($stats{$key}{$_});
        }
    }
    $msg .= ", ";
}

$msg .= sprintf('query time %dms QTime: %dms |', $query_time, $query_qtime);
$msg .= $msg2;
msg_perf_thresholds() if $stat;
$msg .= sprintf(' query_time=%dms query_QTime=%dms', $query_time, $query_qtime);

vlog2;
quit $status, $msg;
