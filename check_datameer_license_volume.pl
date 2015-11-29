#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 20:59:05 +0000 (Thu, 05 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file

# http://documentation.datameer.com/documentation/display/DAS30/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check Datameer license volume used % using Datameer Rest API

Datameer is licensed by Cumulative Data Ingested Volume so this is an important thing to monitor and graph through the year and set thresholds on

Tested against Datameer 3.0.11 and 3.1.1

Note: Datameer 3.0 first release or two had a bug in it's license calculation such that the reported license data used was too high due to counting all data transformations instead of just data ingested";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $default_warning  = 80;
my $default_critical = 90;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    %datameer_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold % for data license volume used (default: $default_warning)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold % for data license volume used (default: $default_critical)" ],
);
@usage_order = qw/host port user password warning critical/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 0 } );

my $url = "http://$host:$port/rest/license-details";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

my $content = curl $url, "Datameer", $user, $password;

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "CRITICAL", "invalid json returned by '$host:$port'";
};

foreach(qw/TotalVolumeConsumedInBytes LicenseVolumelimitInBytes LicenseVolumePeriodInMonths/){
    unless(defined($json->{$_})){
        quit "UNKNOWN", "$_ was not defined in json output returned from Datameer server. API may have changed. $nagios_plugins_support_msg";
    }
    vlog2 sprintf("%s = %s", $_, $json->{$_});
}

my $volume_used_pc;

# unlimited, eg. Evaluation license
if($json->{"LicenseVolumelimitInBytes"} < 0){
    $json->{"LicenseVolumelimitInBytes"} = 0;
    $volume_used_pc = 0;
} else {
    my $volume_used_pc = sprintf("%.2f", $json->{"TotalVolumeConsumedInBytes"} / $json->{"LicenseVolumelimitInBytes"});
}
vlog2 sprintf("Volume Used %% = %s", $volume_used_pc);

$msg = sprintf("%s%% license volume used", trim_float($volume_used_pc));
check_thresholds($volume_used_pc);
$msg .= sprintf(", %s / %s, %s month licensing period | license_volume_used=%.2f%%%s license_volume_used=%dB;;0;%d",
                    human_units($json->{"TotalVolumeConsumedInBytes"})  ,
                    human_units($json->{"LicenseVolumelimitInBytes"})   ,
                                $json->{"LicenseVolumePeriodInMonths"}  ,
                                $volume_used_pc                         ,
                                msg_perf_thresholds(1)                  ,
                                $json->{"TotalVolumeConsumedInBytes"}   ,
                                $json->{"LicenseVolumelimitInBytes"}    ,
                    );

vlog2;
quit $status, $msg;
