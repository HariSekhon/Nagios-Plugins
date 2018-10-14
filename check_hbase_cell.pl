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

$DESCRIPTION = "Nagios Plugin to check a specific HBase table cell via the HBase Thrift API Server

1. reads a specified HBase cell given a table, row key and column family:qualifier
2. checks cell's returned value against expected regex (optional)
3. checks cell's returned value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number
4. outputs the connect+query time to a given precision for reporting and graphing
5. optionally outputs the cell's value for graphing purposes

Requires the CPAN Thrift perl module

HBase Thrift bindings were generated using Thrift 0.9.0 on CDH 4.3 (HBase 0.94.6-cdh4.3.0) CentOS 6.4 and placed under lib/Hbase

See also:

- check_hbase_cell.py -  uses a dedicated Thrift module for configurability.
- check_hbase_cell_stargate.pl - uses the Stargate REST API

Tested on CDH 4.3, 4.5 and Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1
";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::HBase;
use HariSekhon::HBase::Thrift;
use Data::Dumper;
use Thrift;
use Thrift::Socket;
use Thrift::BinaryProtocol;
use Thrift::BufferedTransport;
use Time::HiRes 'time';
# Thrift generated bindings for HBase, provided in lib
use Hbase::Hbase;

set_port_default(9090);

my $table;
my $row;
my $column;
my $expected;
my $graph;
my $units;

my $default_precision = 4;
my $precision = $default_precision;

env_creds(["HBASE_THRIFT", "HBASE"], "HBase Thrift Server");

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

vlog2;
set_timeout();

my $send_timeout = minimum_value(($timeout*1000) - 1000, 1000);
my $recv_timeout = $send_timeout;
vlog2 sprintf("calculated Thrift send timeout as %s secs", $send_timeout / 1000);
vlog2 sprintf("calculated Thrift recv timeout as %s secs", $recv_timeout / 1000);
vlog2;

my $start_time = time;
my $client = connect_hbase_thrift($host, $port, $send_timeout, $recv_timeout);

my $cell;
my $cell_info = "HBase table '$table' row '$row' column '$column'";
try{
    $cell = $client->get($table, $row, $column);
    unless($cell){
        quit "CRITICAL", "no cell object returned for $cell_info";
    }
};
# would use catch_quit but the API returns just the table name for invalid table so have to handle specially :-/
catch {
    my $err = "failed to retrieve cell for $cell_info";
    if(defined($@->{"message"})){
        $err .= ":" . ref($@) . ": ";
        if($@->{"message"} eq $table){
            $err .= "table $table not found?";
        } else {
            $err .= $@->{"message"};
        }
    }
    quit "CRITICAL", $err;
};
my $time   = sprintf("%0.${precision}f", time - $start_time);

print Dumper($cell) if ($debug or $verbose >= 3);

# Check first struct returned
$cell = @{$cell}[0];

unless(exists($cell->{"value"})){
    quit "CRITICAL", "no value defined for column $column in table '$table' row '$row'";
}

my $value = $cell->{"value"};

vlog2 "cell value = $value\n";

$status = "OK";

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
