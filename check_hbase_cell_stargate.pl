#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-13 02:30:13 +0100 (Sun, 13 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a specific HBase table cell via the HBase Stargate REST API Server

1. reads a specified HBase cell given a table, row key and column family:qualifier
2. checks cell's returned value against expected regex (optional)
3. checks cell's returned value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number
4. outputs the query time to a given precision for reporting and graphing
5. optionally outputs the cell's value for graphing purposes

Tested on CDH 4.3, 4.5 and Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

Limitations:

Any non-existent table/row/column will result in:

UNKNOWN: 404 Not Found

since this is all the Stargate server gives us for a response.

Another option is to use check_hbase_cell.pl / check_hbase_cell_thrift.pl which uses the Thrift API and has better error reporting
";

$VERSION = "0.6.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::HBase;
use Data::Dumper;
use MIME::Base64;
use LWP::Simple '$ua';
use Time::HiRes 'time';
use URI::Escape;
use XML::Simple;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8080);

my $table;
my $row;
my $column;
my $expected;
my $graph;
my $units;

my $default_precision = 4;
my $precision = $default_precision;

env_creds(["HBASE_STARGATE", "HBASE"], "HBase Stargate Rest API server");


%options = (
    %hostoptions,
    "T|table=s"     => [ \$table,       "Table to query" ],
    "R|row=s"       => [ \$row,         "Row   to query" ],
    "C|column=s"    => [ \$column,      "Column family:qualifier to query" ],
    "e|expected=s"  => [ \$expected,    "Expected regex for the cell's value. Optional" ],
    %thresholdoptions,
    "p|precision=s" => [ \$precision,   "Precision for query timing in decimal places (default: $default_precision)" ],
    "g|graph"       => [ \$graph,       "Graph the cell's value. Optional, use only if a floating point number is normally returned for it's values, otherwise will print NaN (Not a Number). The reason this is not determined automatically is because keys that change between floats and non-floats will result in variable numbers of perfdata tokens which will break PNP4Nagios" ],
    "u|units=s"     => [ \$units,       "Units to use if graphing cell's value. Optional" ],
);
@usage_order = qw/host port table row column expected warning critical precision graph units/;

get_options();

$host       = validate_host($host);
$host       = validate_resolvable($host);
$port       = validate_port($port);
$table      = validate_database_tablename($table, "HBase", "allow_qualified");
$row        = validate_hbase_rowkey($row);
$column     = validate_hbase_column_qualifier($column);
if(defined($expected)){
    $expected = validate_regex($expected);
}
vlog_option "graph", "true" if $graph;
$units     = validate_units($units) if defined($units);
$precision = validate_int($precision, "precision", 1, 20);
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 0, "integer" => 0 } );

my $cell_info = "table '$table' row '$row' column '$column'";

my $url = "http://$host:$port/" . uri_escape($table) . "/" . uri_escape($row) . "/" . uri_escape($column) . "?v=1";
vlog_option "url", $url;

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $start_time = time;
my $content    = curl $url, "HBase Stargate";
my $time       = sprintf("%0.${precision}f", time - $start_time);

if($content =~ /\A\s*\Z/){
    quit "CRITICAL", "empty body returned from '$url'";
}

# HBase 1.2 returns the key without XML, causing XMLin to assume it's a file instead
my $value;
if($content =~ /^\s*</){
    my $xml;
    try{
        $xml = XMLin($content, forcearray => 1, keyattr => []);
    };
    catch {
        if($@ =~ /read error/){
            $@ = "XML parsing error: " . join(', ', $@);
        }
        quit "CRITICAL", strip($@);
    };

    print Dumper($xml) if($debug or $verbose >= 3);

    # Tested that the latest value (newest timestamp) is indeed returned first in the Row list
    # but now optimized this to only return one version (the latest version)
    unless(defined($xml->{"Row"}[0]->{"key"})){
        quit "CRITICAL", "row key not defined in returned results";
    }

    my $rowkey = $xml->{"Row"}[0]->{"key"};
    $rowkey = decode_base64($rowkey);
    vlog2 "row key    = $rowkey";

    vlog2 "checking we're got the right row key, column family:qualifier";
    unless($rowkey eq $row){
        quit "CRITICAL", "wrong row returned, expected row '$row', got row '$rowkey'";
    }

    unless(defined($xml->{"Row"}[0]->{"Cell"}[0]->{"column"})){
        quit "CRITICAL", "column not defined in first returned result";
    }

    my $column_returned = $xml->{"Row"}[0]->{"Cell"}[0]->{"column"};
    $column_returned    = decode_base64($column_returned);
    vlog2 "column     = $column_returned";

    unless($column_returned eq $column){
        quit "CRITICAL", "wrong column family:qualifier returned, expected column '$column', got column '$column_returned'";
    }

    unless(defined($xml->{"Row"}[0]->{"Cell"}[0]->{"content"})){
        quit "CRITICAL", "Cell content not found in XML response from HBase Stargate server";
    }

    $value = $xml->{"Row"}[0]->{"Cell"}[0]->{"content"};
    $value = decode_base64($value);
} else {
    $value = $content;
}
vlog2 "cell value = $value\n";

if(defined($expected)){
    vlog2 "checking cell value '$value' against expected regex '$expected'\n";
    unless($value =~ $expected){
        quit "CRITICAL", "cell value did not match expected regex (value: '$value', expected regex: '$expected') for $cell_info";
    }
}

$msg = "cell value = '$value' for $cell_info";

my $isFloat = isFloat($value);
my $non_float_err = "cell value '$value' is not a floating point number for $cell_info";
if($critical){
    unless($isFloat){
        critical;
        $msg = $non_float_err;
    }
} elsif($warning){
    unless($isFloat){
        warning;
        $msg = $non_float_err;
    }
}

if($isFloat){
    check_thresholds($value);
}
$msg .= " |";
if($graph){
    if($isFloat){
        $msg .= " value=$value";
        $msg .= $units if $units;
        msg_perf_thresholds();
    } else {
        $msg .= " value=NaN";
    }
}
$msg .= " query_time=${time}s";

quit $status, $msg;
