#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-16 15:21:43 +0000 (Mon, 16 Feb 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Solr / SolrCloud metrics via Solr API

There are too many metrics to practically output at the same time so you must at the least specify a category and possibly a specific metric --key to return. Use the --list-categories/--list-keys switches to find out what categories and keys are available.

Additionally, can drill down to a specific --stat to collect from that metric.

Optional thresholds apply if specifying a single --stat.

Tested on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6";

# Some useful metrics to collect
#
# Number of docs
# Number of queries / queries per second
# Average response time
# Number of updates
# Cache hit ratios
# Replication status
# Synthetic queries

our $VERSION = "0.6.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;
use URI::Escape;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $category;
my $key;
my $list_categories;
my $list_keys;
my $stat;
my %stats;

%options = (
    %solroptions,
    %solroptions_collection,
    "A|cat|category=s" => [ \$category,         "Category of statistics to return (required unless doing --list-categories)" ],
    "K|key=s"          => [ \$key,              "Specific metrics to fetch by key name (case sensitive, optional)" ],
    "s|stat=s"         => [ \$stat,             "Stat for given metric key, optional thresholds will apply to this if specified" ],
    "list-categories"  => [ \$list_categories,  "List metric categories and exit" ],
    "list-keys"        => [ \$list_keys,        "List metric keys for a given category and exit" ],
    %solroptions_context,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/collection category key stat list-collections list-categories list-keys http-context/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$collection = validate_solr_collection($collection) unless $list_collections;
unless($list_categories){
    $category = validate_alnum($category, "category");
    # Solr Categories are case sensitive uppercase otherwise nothing is returned
    $category = uc $category;
}
if(defined($key)){
    #$key = validate_alnum($key, "key");
    $key =~ /^([\w\/][\.\w\@\[\]\/\s-]+[\w\/])$/ or usage "invalid key defined, must be alphanumeric with dots to separate mbean from metric key";
    $key = $1;
    #$stat = $2 if $2;
    validate_thresholds();
}
$stat = validate_chars($stat, "stat", "A-Za-z0-9_") if defined($stat);
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

my $url = "$http_context/$collection/admin/mbeans?stats=true";
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
    quit "UNKNOWN", "no metrics returned for category '$category'" . ( defined($key) ? " key '$key'" : "" ). ", did you specify a correct category as listed by --list-categories" . ( defined($key) ? " and correct key as listed by --list-keys?" : "?");
}

#my $key_found  = 0;
my $stat_found = 0;
# This construct is the more general purpose left over from parsing all the metric categories, still viable now using only a single category
foreach (my $i = 1; $i < scalar @mbeans; $i+=2){
    isHash($mbeans[$i]) or quit "UNKNOWN", "mbean member $i is not a hashref, got '$mbeans[$i]'. $nagios_plugins_support_msg_api";
    #print "i $i => " . Dumper($mbeans[$i]);
    foreach my $key2 (keys %{$mbeans[$i]}){
        # if specifying wrong key then whole hash is empty so this logic is redundant
        #if($key and $key eq $key2){
        #    $key_found = 1;
        #}
        my $key2_dot = $key2;
        $key2_dot =~ s/\./\\./g;
        # When the stats field is null it results in the following warnings, which we temporarily suppress here:
        #
        # Odd number of elements in hash assignment at ./check_solr_metrics.pl line 135.
        # Use of uninitialized value in list assignment at ./check_solr_metrics.pl line 135.
        no warnings;
        my %keys3;
        # For some unknown reason the API returns this data as an array instead of a hash for this key, see issue # 127
        if($key2 =~ /^org.apache.solr.handler.dataimport.DataImportHandler|\/dataimport$/){
            %keys3 = get_field2_array($mbeans[$i], "$key2_dot.stats", 1);
        } else {
            %keys3 = get_field2_hash($mbeans[$i], "$key2_dot.stats", 1);
        }
        use warnings;
        if(%keys3){
            foreach (sort keys %keys3){
                if($stat){
                    next unless $_ =~ /^(.*\.)?$stat$/;
                }
                $stat_found = 1;
                my $value = $keys3{$_};
                # org.apache.solr.handler.dataimport.DataImportHandler returns these, see issue # 127
                $value =~ s/^java\.util\.concurrent\.atomic\.AtomicLong://;
                if(defined($value) and isFloat($value)){
                    if(defined($stats{"${key2}.$_"})){
                        code_error "duplicate key '${key2}.$_' detected";
                    }
                    # normalize new 7.x format back to old short format
                    $_ =~ s/^.*\.//;
                    vlog2 "$key2 => $_  = $value";
                    $stats{$key2}{$_} = $value;
                } elsif($stat and not isFloat($value)){
                    quit "UNKNOWN", "stat '$stat' for metric '$key2' is not numeric ('$value'), cannot be a statistic. Please specify a numeric statistic field instead, omit --stat to see the full list of valid metric stats";
                }
            }
        }
    }
}

unless(%stats){
    # never hits this since specifying either incorrect category or key returns empty hash
#    if($key){
#        if($key_found){
#            quit "UNKNOWN", "no stats returned for category '$category' key '$key'";
#        } else {
#            quit "UNKNOWN", "key '$key' was not found, did you specify the correct key name? See --list-keys";
#        }
    if($stat){
        if($stat_found){
            quit "UNKNOWN", "no stat returned for category '$category' key '$key' stat '$stat'";
        } else {
            quit "UNKNOWN", "stat not found for category '$category' key '$key' stat '$stat', did you specify the correct stat name? Try omitting it to see what stats are returned for this category";
        }
    } else {
        quit "UNKNOWN", "no stats collected. Stats may be null or $nagios_plugins_support_msg_api"
    }
}

$msg .= "Solr " . lc $category . " ";
my $msg2;
my $num_stats = 0;
foreach(keys %stats){
    $num_stats += scalar keys %{$stats{$_}};
}
vlog2 "$num_stats stats collected";
foreach my $key (sort keys %stats){
    $msg .= "$key ";
    foreach(sort keys %{$stats{$key}}){
        #print "$_=$stats{$_}\n";
        $msg  .= "$_=$stats{$key}{$_}, ";
        $msg2 .= " '${key} $_'=$stats{$key}{$_}";
        if($num_stats == 1){
            check_thresholds($stats{$key}{$_});
        }
    }
}

$msg .= sprintf('query time %dms, QTime %dms |', $query_time, $query_qtime);
$msg .= $msg2;
msg_perf_thresholds() if $stat;
$msg .= sprintf(' query_time=%dms query_QTime=%dms', $query_time, $query_qtime);

vlog2;
quit $status, $msg;
