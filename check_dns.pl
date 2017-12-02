#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-05-11 15:49:14 +0100 (Fri, 11 May 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

my @valid_types = qw/A MX NS PTR SOA SRV TXT/;

$DESCRIPTION = "Nagios Plugin to test a DNS record

Primarily written to check things like NS and MX records for domains which the standard check_dns Nagios plugin can't do.

Full list of supported record types: " . join(", ", @valid_types) . "

The regex if supplied is validated against each record returned and it is anchored (^regex\$) as that's normally what you want to make it easier to strictly validate IP / name results, but if testing partial TXT records you may need to use .* before and after the regex, eg. '.*spf.*'. If differing TXT records are returned then use alternation '|' as per regex standard to be able to match both types of records, eg. 'regex1|regex2', see tests/test_dns.sh for an example. Requiring validating every record is much safer to ensure there is no rogue DNS server injected in to your domain and anchoring prevents a regex of 10\.10\.10\.10 from matching an unexpected service on 10.10.10.100

TLDs are validated with the following files:

* lib/resources/tlds-alpha-by-domain.txt
* lib/resources/custom_tlds.txt

If you need a custom TLD, please add it to custom_tlds.txt.
";

# TODO: root name servers switch, determine root name servers for the specific TLD and go straight to them to bypass intermediate caching

$VERSION = "0.8.4";

use strict;
use warnings;
use Net::DNS;
use Time::HiRes 'time';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use Data::Dumper;
use List::Util 'shuffle';

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
my $randomize_servers;

%options = (
    "s|server=s"            => [ \$server,          "DNS server(s) to query, can be a comma separated list of servers" ],
    "r|record=s"            => [ \$record,          "DNS record to query"  ],
    "q|type=s"              => [ \$type,            "DNS query type (defaults to '$default_type' record)"  ],
    "e|expected-result=s"   => [ \$expected_result, "Expected results, comma separated" ],
    "R|expected-regex=s"    => [ \$expected_regex,  "Expected regex to validate against each returned result (anchored, so if testing partial TXT records you may need to use .* before and after the regex, and if differing TXT records are returned then use alternation '|' to support the different regex, see tests/test_dns.sh for an example)" ],
    "A|randomize-servers"   => [ \$randomize_servers, "Randomize the order of DNS servers" ],
    "N|no-uniq-results"     => [ \$no_uniq_results, "Test and display all results, not only unique results" ]
);

@usage_order = qw/server record type expected-result expected-regex randomize-servers no-uniq-results/;
get_options();

$server or usage "server(s) not specified";
@servers = split(/\s*[,\s]\s*/, $server);
for(my $i=0; $i < scalar @servers; $i++){
    $servers[$i] = validate_host($servers[$i]);
}
grep($type, @valid_types) or usage "unsupported type '$type' given, must be one of: " . join(",", @valid_types);
if($type eq "PTR"){
    $record = isIP($record) or usage "invalid record given for type PTR, should be an IP";
} elsif($type eq "SRV"){
    $record =~ /^[A-Za-z_\.-]+\.$domain_regex/ or usage "invalid record given for type SRV, must contain only alphanumeric, underscores, dashes followed by a valid domain name format";
} else {
    $record = isDomain($record) or isFqdn($record) or usage "invalid record given, should be a domain or fully qualified host name";
}
vlog_option "server", join(",", @servers);
vlog_option "record", $record;
vlog_option "type",   $type;
if($randomize_servers){
    vlog2 "randomizing nameserver list";
    @servers = shuffle(@servers);
    vlog_option "servers", join(",", @servers);
}

my @expected_results;
if($expected_result){
    @expected_results = sort split(/\s*,\s*/,   $expected_result);
    if($type eq "A"){
        foreach(@expected_results){
            isIP($_) or usage "invalid expected result '$_' for A record, should be an IP address";
        }
    } elsif(grep($type, qw/CNAME MX NS PTR/)){
        foreach(@expected_results){
            isFqdn($_) or usage "invalid expected result '$_' for CNAME/MX/NS/PTR record, should be an fqdn";
        }
    }
    vlog_option "expected results", $expected_result;
}
$expected_regex2 = validate_regex($expected_regex) if defined($expected_regex);

vlog2;
set_timeout();

$status = "OK";

my @resolved_dns_servers;
for(my $i=0; $i < scalar @servers; $i++){
    $servers[$i] = resolve_ip($servers[$i]) || next;
    push(@resolved_dns_servers, $servers[$i]);
}
@resolved_dns_servers || quit "CRITICAL", "no given DNS servers resolved to IPs, cannot query them";

my $res = Net::DNS::Resolver->new(
    nameservers => [@resolved_dns_servers],
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
vlog2;
plural @servers;
$query or quit "CRITICAL", "query returned with no answer from server$plural " . join(",", @servers) . " in $total_time secs" . ( $verbose ? " for record '$record' type '$type'" : "");
vlog2 "query returned in $total_time secs";
my $perfdata = " | dns_query_time='${total_time}s'";

vlog3 "returned records:\n";
foreach my $rr ($query->answer){
    vlog3 Dumper($rr);
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
    } elsif($rr->type eq "SOA"){
        $result = $rr->serial;
    } elsif($rr->type eq "SRV"){
        $result = $rr->target;
    } elsif($rr->type eq "TXT"){
        $result = $rr->txtdata;
    } else {
        quit "UNKNOWN", "unknown/unsupported record type '$rr->type' returned for record '$record'";
    }
    vlog2 "got result: $result\n";
    if($type eq "A"){
        isIP($result) or quit "CRITICAL", "invalid result '$result' returned for A record by DNS server, expected IP address for A record$perfdata";
    } elsif(grep { $type eq $_ } qw/CNAME MX NS PTR SRV/){
        isFqdn($result) or quit "CRITICAL", "invalid result '$result' returned " . ($verbose ? "for record '$record' type '$type' ": "") . "by DNS server, expected FQDN for this record type$perfdata";
    } elsif($type eq "SOA"){
        isInt($result) or quit "CRITICAL", "invalid serial result '$result' returned for SOA record " . ($verbose ? "'$record' ": "") . "by DNS server, expected an unsigned integer$perfdata";
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
    $msg .= "regex validation failed on '" . join("','", @regex_mismatches) . "' against regex '$expected_regex', returns '";
} elsif($type eq "SOA"){
    $msg .= "return serial '";
} else {
    $msg .= "returns '";
}
if($no_uniq_results){
    $msg .= join("','", @results);
} else {
    $msg .= join("','", @results_uniq);
}
$msg .= "'";
$msg .= " in $total_time secs" if $verbose;
$msg .= $perfdata;

my $extended_command = dirname $progname;
$extended_command .= "/$progname -s $server -r $record -q $type";
$extended_command .= " -e $expected_result"  if $expected_result;
$extended_command .= " -R '$expected_regex'" if $expected_regex;
$extended_command .= " -t $timeout"          if($timeout ne $timeout_default);
vlog3 "\nextended command: $extended_command\n\n";

quit $status, $msg;
