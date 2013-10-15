#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-05-11 15:49:14 +0100 (Fri, 11 May 2012)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to test a DNS record

Primarily written to check things like NS and MX records for domains
which the standard check_dns Nagios plugin can't do";

# TODO: root name servers switch, determine root name servers for the specific TLD and go straight to them to bypass intermediate caching

$VERSION = "0.7.3";

use strict;
use warnings;
use Net::DNS;
use Time::HiRes 'time';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$status_prefix = "DNS";
my $default_type = "A";
my $type = $default_type;
my $record;
my $server;
my @servers;
my $expected_result;
my $expected_regex;
my $expected_regex2;
my $no_uniq_results;

# TODO: add SRV support
my @valid_types = qw/A MX NS PTR TXT/;

%options = (
    "s|server=s"            => [ \$server,          "DNS server(s) to query, can be a comma separated list of servers" ],
    "r|record=s"            => [ \$record,          "DNS record to query"  ],
    "q|type=s"              => [ \$type,            "DNS query type (defaults to '$default_type' record)"  ],
    "e|expected-result=s"   => [ \$expected_result, "Expected results, comma separated" ],
    "R|expected-regex=s"    => [ \$expected_regex,  "Expected regex to validate against each returned result" ],
    "no-uniq-results"       => [ \$no_uniq_results, "Test and display all results, not only unique results" ]
);

@usage_order = qw/server record type expected-result expected-regex/;
get_options();

$server or usage "server(s) not specified";
@servers = split(/\s*[,\s]\s*/, $server);
foreach(@servers){
    $_ = isHostname($_) || isIP($_) || usage "invalid server '$_' given, should be a hostname or IP address";
}
grep($type, @valid_types) or usage "unsupport type '$type' given, must be one of: " . join(",", @valid_types);
if($type eq "PTR"){
    $record = isIP($record) or usage "invalid record given for type PTR, should be an IP";
} else {
    $record = isDomain($record) or isFqdn($record) or usage "invalid record given, should be a domain or fully qualified host name";
}
vlog_options "server", join(",", @servers);
vlog_options "record", $record;
vlog_options "type",   $type;

my @expected_results;
if($expected_result){
    @expected_results = sort split(/\s*,\s*/, $expected_result);
    if($type eq "A"){
        foreach(@expected_results){
            isIP($_) or usage "invalid expected result '$_' for A record, should be an IP address";
        }
    } elsif(grep($type, qw/CNAME MX NS PTR/)){
        foreach(@expected_results){
            isFqdn($_) or usage "invalid expected result '$_' for CNAME/MX/NS/PTR record, should be an fqdn";
        }
    }
    vlog_options "expected results", $expected_result;
}
$expected_regex2 = validate_regex($expected_regex) if defined($expected_regex);

vlog2;
set_timeout();

$status = "OK";

my $res = Net::DNS::Resolver->new(
    nameservers => [@servers],
    recurse     => 1,
    debug       => $debug,
);
vlog2 "created resolver pointing to " . join(",", @servers);
$res->tcp_timeout(2);
$res->udp_timeout(2);
vlog2 "set resolver timeout to 2 secs per server";

my @results;
my @rogue_results;
my @missing_results;

vlog2 "sending query for $record $type record";
my $start = time;
my $query = $res->query($record, $type);
my $stop  = time;
my $total_time = sprintf("%.4f", $stop - $start);
$query or quit "CRITICAL", "query returned with no answer from servers " . join(",", @servers) . " in $total_time secs";
vlog2 "query returned in $total_time secs";
my $perfdata = "| dns_query_time='${total_time}s'";

foreach my $rr ($query->answer){
    my $result;
     if($rr->type eq "A"){
        $result = $rr->address;
    } elsif($rr->type eq "CNAME"){
        $result = $rr->cname;
        $result =~ s/\.$//;
    } elsif($rr->type eq "MX"){
        $result = $rr->exchange;
    } elsif($rr->type eq "NS"){
        $result = $rr->nsdname;
    } elsif($rr->type eq "PTR"){
        $result = $rr->ptrdname;
    } elsif($rr->type eq "TXT"){
        $result = $rr->txtdata;
    } else {
        quit "UNKNOWN", "unknown/unsupported record type '$rr->type' returned for record '$record'";
    }
    vlog2 "got result: $result";
    if($type eq "A"){
        isIP($result) or quit "CRITICAL", "invalid result '$result' returned for A record by DNS server, expected IP address for A record$perfdata";
    } elsif(grep($type, qw/CNAME MX NS PTR/)){
        isFqdn($result) or quit "CRITICAL", "invalid result '$result' returned by DNS server, expected FQDN for this record type$perfdata";
    }
    push(@results, $result);
    if(@expected_results){
        unless(grep(lc $_ eq lc $result, @expected_results)){
            vlog3 "result '$result' wasn't found in expected results, added to rogue list";
            push(@rogue_results, $result);
        }
    }
}

@results or quit "CRITICAL", "no result received for '$record' $type record from servers " . join(",", @servers) . " in $total_time secs";

my @results_uniq = sort(uniq_array(@results));

foreach my $expected_result2 (@expected_results){
    unless(grep(lc $_ eq lc $expected_result2, @results_uniq)){
        vlog3 "$expected_result2 wasn't found in results, adding to missing list";
        push(@missing_results, $expected_result2);
    }
}

my @regex_mismatches;
if($expected_regex2){
    foreach my $result (@results){
        $result =~ /^$expected_regex2$/ or push(@regex_mismatches, $result);
    }
}
@regex_mismatches = sort(uniq_array(@regex_mismatches)) if(@regex_mismatches);

$msg .= "$record $type record ";

if(scalar @rogue_results or scalar @missing_results){
    critical;
    $msg .= "mismatch, expected '" . join(",", @expected_results) . "', got '";
} elsif(scalar @regex_mismatches){
    critical;
    $msg .= "regex validation failed on '" . join(",", @regex_mismatches) . "' against regex '$expected_regex', returns '";
} else {
    $msg .= "returns '";
}
if($no_uniq_results){
    $msg .= join(",", @results);
} else {
    $msg .= join(",", @results_uniq);
}
$msg .= "'";
$msg .= " in $total_time secs" if $verbose;
$msg .= $perfdata;

my $extended_command = dirname $progname;
$extended_command .= "/$progname -s $server -r $record -q $type";
$extended_command .= " -e $expected_result" if $expected_result;
$extended_command .= " -R '$expected_regex'" if $expected_regex;
$extended_command .= " -t $timeout"   if($timeout ne $timeout_default);
vlog3 "\nextended command: $extended_command\n\n";

quit $status, $msg;
