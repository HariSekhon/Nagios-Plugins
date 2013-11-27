#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to the number of running Datameer jobs using the Datameer Rest API

Tested against Datameer 2.0.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS;
use LWP::UserAgent;
use Time::Local;

my $default_port = 8080;
$port = $default_port;

%options = (
    "H|host=s"         => [ \$host,         "Datameer server" ],
    "P|port=s"         => [ \$port,         "Datameer port (default: $default_port)" ],
    "u|user=s"         => [ \$user,         "User to connect with (\$DATAMEER_USER)" ],
    "p|password=s"     => [ \$password,     "Password to connect with (\$DATAMEER_PASSWORD)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold (inclusive)" ],
);

@usage_order = qw/host port user password warning critical/;

if(defined($ENV{"DATAMEER_USER"})){
    $user = $ENV{"DATAMEER_USER"};
}
if(defined($ENV{"DATAMEER_PASSWORD"})){
    $password = $ENV{"DATAMEER_PASSWORD"};
}

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1} );

my $url = "http://$host:$port/rest/jobs/list-running";

vlog2;
set_timeout();

$status = "OK";

my $ua = LWP::UserAgent->new;
#$ua->agent("Hari Sekhon $prog $main::VERSION");
$ua->credentials($host, '', $user, $password);

# Lifted from check_cloudera_manager_metrics.pl TODO: move to lib
#my $content = get $url;
vlog2 "querying $url";
my $req = HTTP::Request->new('GET',$url);
$req->authorization_basic($user, $password);
my $response = $ua->request($req);
my $content  = $response->content;
chomp $content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http code: " . $response->code;
vlog2 "message: " . $response->message;

unless($response->code eq "200"){
    quit "UNKNOWN", $response->code . " " . $response->message;
}

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "CRITICAL", "invalid json returned by '$host:$port'";
};

my $running_jobs = 0;
my %job_statuses = (
    "running"               => 0,
    "waiting_for_other_job" => 0,
);
foreach(@{$json}){
    vlog3 "job: $_";
    $running_jobs++;
    defined($_->{"jobStatus"}) or quit "UNKNOWN", "no jobstatus returned from Datameer server. Format may have changed. $nagios_plugins_support_msg";
    $job_statuses{lc $_->{"jobStatus"}}++;
}

$msg = "active jobs=$running_jobs";

check_thresholds($running_jobs);

foreach(sort keys %job_statuses){
    $msg .= ", $_=$job_statuses{$_}";
}

$msg .= " | active_jobs=$running_jobs";
msg_perf_thresholds();

# Not adding variable perdata args as that can break PNP4Nagios
#foreach(sort keys %job_statuses){
foreach(qw/running waiting_for_other_job/){
    $msg .= " $_=$job_statuses{$_}";
}

vlog2 if is_ok;
quit $status, $msg;
