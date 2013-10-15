#!/usr/bin/perl
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-08-22 15:56:27 +0000 (Mon, 22 Aug 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check MySQL arbitrary queries against regex matches or numerical ranges, with perfdata support";

# TODO: add retry switch if valid below threshold

# DO NOT ADD a semi-colon to the end of your query in Nagios, although the plugin can handle this fine and it works on the command line, in Nagios the command will end up being prematurely terminated and result in a null critical error that is hard to debug and that this plugin cannot catch since it's raised by the shell before plugin is executed

$VERSION = "0.9.12";

use strict;
use warnings;
use Time::HiRes;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

use DBI;

my $default_port = 3306;
my $default_message = "query returned";
my $database = "";
my $epoch;
my $host;
my $port = $default_port;
my $user = "";
my $password = "";
my $query;
my $field = 1;
my $graph;
my $label;
my $message = $default_message;
my $message_pre;
my $message_printf = 0;
my $message_printf_numeric = 0;
my $no_querytime = 0;
my $output;
my $regex;
my $short;
my $units = "";

%options = (
    "H|host=s"      => [ \$host,     "MySQL Host" ],
    "P|port=s"      => [ \$port,     "MySQL Port" ],
    "u|user=s"      => [ \$user,     "MySQL user" ],
    "p|password=s"  => [ \$password, "MySQL password" ],
    "d|database=s"  => [ \$database, "MySQL database" ],
    "q|query=s"     => [ \$query,    "MySQL query to execute" ],
    "f|field=s"     => [ \$field,    "Field number/name to check the results of (defaults to '1')" ],
    "e|epoch"       => [ \$epoch,    "Subtract result from current time in epoch format from result (useful for timestamp based comparisons)" ],
    "m|message=s"   => [ \$message,  "Message to output after result. Can take a printf string with a single substitution (defaults to '$default_message')" ],
    "n|message-prepend" => [ \$message_pre, "Display message before rather than after result (prepend)" ],
    "o|output=s"    => [ \$output,   "Exact output to expect" ],
    "r|regex=s"     => [ \$regex,    "Regex to match the result against" ],
    "w|warning=s"   => [ \$warning,  "Warning threshold or ran:ge (inclusive)" ],
    "c|critical=s"  => [ \$critical, "Critical threshold or ran:ge (inclusive)" ],
    "g|graph"       => [ \$graph,    "Perfdata output for graphing" ],
    "l|label=s"     => [ \$label,    "Perfdata label. If not specified uses field name or Undefined if field name doesn't match a known regex of chars" ],
    "U|units=s"     => [ \$units,    "Units of measurement for graphing output (%/s/ms/us/B/KB/MB/TB/c)" ],
    "s|short"       => [ \$short,    "Shorten output, do not output message just result" ],
    "no-querytime"  => [ \$no_querytime, "Do not output the mysql query time" ],
);
@usage_order = qw/host port user password database query field epoch message message-prepend output regex warning critical graph label units short no-querytime/;

#add_options(\%hostoptions);
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$database   = validate_database($database);
$query      = validate_database_query_select_show($query);
$field      = validate_database_fieldname($field);
$regex      = validate_regex($regex) if defined($regex);
$label      = validate_label($label) if($label);
$units      = validate_units($units) if($units);
vlog2("output:    $output") if defined($output);
vlog2("epoch:     on") if $epoch;
validate_thresholds();
$message_pre = 1 if($message eq $default_message);
if($message =~ /^[^%]*\%s[^%]*$/){
    $message_printf = 1;
    vlog2("\nenabling printf string format message (only 1 string printf variable detected)");
} elsif($message =~ /^[^%]*\%(?:\d+)?(?:\.\d+)?[fd][^%]*$/){
    $message_printf_numeric = 1;
    vlog2("\nenabling printf numeric format message (only 1 float/int printf variable detected)");
}
$graph = 1 if $label;
$graph = 1 if $units;
if($graph){
    unless($label){
        $label = "$field";
        $label = validate_label($label);
        vlog2("graphing enabled, defaulting label to $label");
    }
}

vlog2;
set_timeout();

vlog2 "connecting to database";

my $dbh = DBI->connect("DBI:mysql:$database:$host:$port", $user, $password,
                        { Taint      => 1,
                          PrintError => 0,
                          RaiseError => 0 } )
    or quit "CRITICAL", "Couldn't connect to '$host:$port' database '$database' (DBI error: " . DBI->errstr . ")";
vlog2 "login to database successful\n";

# TODO: add multi record support
sub execute_query{
    my $sql = $_[0];
    defined($dbh) or quit "CRITICAL", "database handle no longer valid while attempting to prepare query ($sql)";
    #DBI->trace("SQL");
    my $sth = $dbh->prepare($sql) or quit "CRITICAL", "failed to prepare query: " . $dbh->errstr . " ($sql)";
    vlog2 "query: $sql";
    my $start = Time::HiRes::time;
    $sth->execute or quit "CRITICAL", "Couldn't execute query: " . $sth->errstr . " (\"$sql\")";
    my $stop  = Time::HiRes::time;
    my $query_time = sprintf("%.4f", $stop - $start);
    vlog2 "query executed in $query_time secs";
    if($sth->rows == 0){
        quit "CRITICAL", "no rows returned by query \"$sql\"";
    }
    my $result;
    if($field =~ /^\d+$/){
        my @data = $sth->fetchrow_array();
        # TODO: better formatting
        print "result row:  " if ($verbose >= 3);
        foreach(@data){
            print "$_ " if ($_ and $verbose >= 3);
        }
        print "\n" if ($verbose >= 3);
        defined($data[$field-1]) or quit "CRITICAL", "couldn't find field $field in result from query \"$sql\"";
        $result = $data[$field-1];
    } else {
        my $data;
        $data = $sth->fetchrow_hashref();
        unless(defined($$data{$field})){
            my $errstr = "couldn't find '$field' field in result from query \"$sql\" (fields returned: ";
            foreach(sort keys %$data){
                $errstr .= "'$_', ";
            }
            $errstr =~ s/, $/)/;
            quit "CRITICAL", $errstr;
        }
        $result = $$data{$field};
    }
    $sth->finish();
    vlog3 "result: $result";
    return ($result, $query_time);
}

my ($result, $query_time) = execute_query($query);
defined($result) or quit "CRITICAL", "no result was received from '$database' database on '$host:$port'";
vlog2;

my $time;
if($epoch){
    isFloat($result) or quit "CRITICAL", "cannot diff result from current epoch time, result is not a number (result: '$result')";
    $time = time;
    vlog3 "epoch time: $time";
    $result = $time - $result;
    vlog2 "result diff: $result";
}

$status = "OK";
if($message_printf){
    $msg   .= sprintf($message, $result);
} elsif($message_printf_numeric and isFloat($result)){
    $msg   .= sprintf($message, $result);
} else {
    $msg   .= "$message " if ($message_pre and not $short);
    $msg   .= "'$result'";
    $msg   .= " $message" unless ($message_pre or $short);
}

if(defined($regex)){
    if($result =~ /$regex/){
        vlog2 "result matched regex $regex\n";
    } else {
        quit "CRITICAL", "$msg (expected regex: '$regex')";
    }
}

if(defined($output)){
    if($result eq $output){
        vlog2 "result matched expected output";
    } else {
        quit "CRITICAL", "$msg (expected: '$output')";
    }
}

if($thresholds{"defined"}){
    #$result =~ /^\d+(?:\.\d+)?$/ or quit "CRITICAL", "result did not match expected thresholds, was not in numeric format (result: '$result')";
    #isFloat($result)
    # Allow for negative numbers
    isFloat($result, 1)
        or quit "CRITICAL", "result did not match expected thresholds, was not in numeric format (result: '$result')";
    check_thresholds($result);
}

$msg .= " | ";
if ($graph and isFloat($result, 1)) {
    $msg .= "'$label'=$result";
    if($units){
        $msg .= $units;
    }
    if($thresholds{"warning"}{"upper"} or $thresholds{"critical"}{"upper"}){
        $msg .= ";" . ( $thresholds{"warning"}{"upper"} ? $thresholds{"warning"}{"upper"} : "" );
        $msg .= ";" . ( $thresholds{"critical"}{"upper"} ? $thresholds{"critical"}{"upper"} : "" );
    }
    $msg .= " ";
}
$msg .= "mysql_query_time=${query_time}s" unless $no_querytime;

quit $status, $msg;
