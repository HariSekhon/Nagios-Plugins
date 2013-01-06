#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-08-11 17:12:01 +0000 (Wed, 11 Aug 2010)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# Nagios Plugin to check SSL Certificate Validity

$VERSION = "0.9.5";

use warnings;
use strict;
use Time::Local;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $openssl          = "/usr/bin/openssl";
$port                = 443;
my $default_critical = 14;
my $default_warning  = 30;

$critical            = $default_critical;
$warning             = $default_warning;

$status = "OK";

my $CApath;
my $cmd;
my $dir_regex = '[\w\.\/-]+';
my $domain;
my $end_date;
my $expected_domain;
my $no_validate;
my $openssl_output_for_shell_regex = '[\w\s_:=@\*,\/\.\(\)\n+-]+';
my $output;
my $returncode;
my @subject_alt_names;
my $subject_alt_names;
my $verify_code = "";
my $verify_msg  = "";
my @output;

my %months = (
    "Jan" => 0,
    "Feb" => 1,
    "Mar" => 2,
    "Apr" => 3,
    "May" => 4,
    "Jun" => 5,
    "Jul" => 6,
    "Aug" => 7,
    "Sep" => 8,
    "Oct" => 9,
    "Nov" => 10,
    "Dec" => 11
);

%options = (
    "H|host=s"                      => [ \$host, "The host to check" ],
    "p|port=i"                      => [ \$port, "The port to check (defaults to port 443)" ],
    "d|domain=s"                    => [ \$expected_domain, "Expected domain of the certificate" ],
    "s|subject-alternative-names=s" => [ \$subject_alt_names, "Additional FQDNs to require on the certificate" ],
    "w|warning=i"                   => [ \$warning, "The warning threshold in days before expiry (defaults to $default_warning)" ],
    "c|critical=i"                  => [ \$critical, "The critical threshold in days before expiry (defaults to $default_critical)" ],
    "C|CApath=s"                    => [ \$CApath, "Path to ssl root certs dir (will attempt to determine from openssl binary if not supplied)" ],
    "N|no-validate"                 => [ \$no_validate, "Do not validate the SSL certificate chain" ]
);
@usage_order = qw/host port domain subject-alternative-names warning critical no-validate CApath/;

get_options();

$host = validate_host($host);
$port = validate_port($port);

if($expected_domain){
    # Allow wildcard certs
    if(substr($expected_domain, 0 , 2) eq '*.'){
        $expected_domain = "*." . validate_domain(substr($expected_domain, 2));
    } else {
        $expected_domain = validate_domain($expected_domain);
    }
}
if($subject_alt_names){
    @subject_alt_names = split(",", "$subject_alt_names");
    foreach(@subject_alt_names){
        validate_domain($_);
    }
}

isInt($warning)  || die "invalid warning threshold given, must be a positive integer\n";
isInt($critical) || die "invalid critical threshold given, must be a positive integer\n";
($critical <= $warning) || die "critical threshold must be less than or equal to the warning threshold\n";

$openssl = which($openssl, 1);

vlog_options "warning  days", $warning;
vlog_options "critical days", $critical;
vlog_options "verbose level", $verbose;
vlog2;

# pkill is available on Linux but not MAC by default, hence using pkill subroutine from my utils instead for portability
set_timeout($timeout, sub { pkill("$openssl s_client -connect $host:$port", "-9") } );

if (defined($CApath)) {
    print "CApath: $CApath\n\n" if $verbose;
} else {
    ($returncode, @output) = cmd("$openssl version -a");
    foreach(@output){
        if (/^OPENSSLDIR: "($dir_regex)"\s*\n?$/) {
            $CApath = $1;
            vlog2 "Found CApath from openssl binary as: $CApath\n";
            last;
        }
    }
    if (not defined($CApath)) {
        usage "CApath to root certs was not specified and could not be found from openssl binary";
    }
}

$CApath = validate_filename($CApath, 1) || die "CApath '$CApath' is invalid\n";

( -e "$CApath" ) || die "CApath directory '$CApath' does not exist!\n";
( -d "$CApath" ) || die "CApath '$CApath' is not a directory!\n";
( -r "$CApath" ) || die "CApath directory '$CApath' was not readable!\n";

vlog2 "* checking validity of cert (chain of trust)";
$cmd = "echo | $openssl s_client -connect $host:$port -CApath $CApath 2>&1";

@output = cmd($cmd);

foreach (@output){
    if(/Connection refused/i){
        quit "CRITICAL", "connection refused";
    } elsif (/^\s*Verify return code: (\d+)\s\((.*)\)$/) {
        $verify_code = $1;
        $verify_msg  = $2;
    } elsif (/^\s*verify error:num=((\d+):(.*))$/) {
        $verify_code = "$verify_code$2,";
        $verify_msg  = "$verify_msg$1, ";
    } elsif (/(.*error.*)/i) {
        $verify_code = 1;
        $verify_msg = "$verify_msg$1, ";
    }
}
($verify_code ne "") or quit "CRITICAL", "Certificate validation failed (failed to find verify code in openssl output - failed to get certificate correctly or possible code error)";
$verify_code =~ s/,\s*$//;
$verify_msg  =~ s/,\s*$//;
vlog2 "Verify return code: $verify_code ($verify_msg)\n";

if (not $no_validate and $verify_code ne 0){
    # Don't handle expiry as part of the cert chain, we want nicer output with more details later
    if(not ( $verify_code eq 10 and $verify_msg =~ /certificate has expired/ ) ){
        quit "CRITICAL", "Certificate validation failed, returned $verify_code ($verify_msg)";
    }
}

$output = join("\n", @output);
$output =~ /^($openssl_output_for_shell_regex)$/ or die "Error: unexpected/illegal chars in openssl output, refused to pass to shell for safety\n";
$output = $1;

vlog2 "* checking domain and expiry on cert";
#$cmd = "echo '$output' | $openssl x509 -noout -enddate -subject 2>&1";
$cmd = "echo '$output' | $openssl x509 -noout -text 2>&1";
@output = cmd($cmd);

foreach (@output){
    #if (/notAfter\=/) {
    if (/Not After\s*:\s*(\w+\s+\d+\s+\d+:\d+:\d+\s+\d+\s+\w+)/) {
        $end_date  = $1;
        #defined($end_date) || quit "CRITICAL", "failed to determine certificate expiry date";
    }
    #elsif (/subject=/) {
    # The * must be in there for wildcard certs
    elsif (/Subject:.+,\s*CN=([\*\w\.-]+)/) {
        $domain = $1;
        #defined($domain) || quit "CRITICAL", "failed to determine certificate domain name";
        last;
    }
}

defined($domain)   or quit "CRITICAL", "failed to determine certificate domain name";
defined($end_date) or quit "CRITICAL", "failed to determine certificate expiry date";
vlog2 "Domain: $domain";
vlog2 "Certificate Expires: $end_date\n";

my ($month, $day, $time, $year, $tz) = split(/\s+/, $end_date);
my ($hour, $min, $sec)               = split(/\:/, $time);

my $expiry    = timegm($sec, $min, $hour, $day, $months{$month}, $year-1900);
my $now       = time;
my $days_left = int( ($expiry - $now) / (86400) );

vlog2 "* checking expected domain name on cert\n";
if ($expected_domain and $domain ne $expected_domain) {
    $status = "CRITICAL";
    $msg .= "domain '$domain' did not match expected domain '$expected_domain'! ";
}

my $plural = "";
my $san_names_checked = 0;
if($subject_alt_names){
    vlog2 "* testing subject alternative names";
    my @found_alt_names   = ();
    my @missing_alt_names = ();
    foreach my $subject_alt_name (@subject_alt_names){
        $san_names_checked += 1;
        vlog2 "* checking subject alternative name: '$subject_alt_name'";
        foreach (@output){
            if(/\bDNS:$subject_alt_name\b/){
                push(@found_alt_names, $subject_alt_name);
            }
        }
        if (not grep { $_ eq $subject_alt_name } @found_alt_names){
            push(@missing_alt_names, $subject_alt_name);
            $status = "CRITICAL";
        }
    }
    if(scalar @missing_alt_names){
        if(scalar @missing_alt_names > 1){
            $plural = "s";
        }
        $msg .= scalar @missing_alt_names . " SAN name$plural missing: " . join(",", @missing_alt_names) . ".";
    }
    vlog2 "";
}

if($status ne "CRITICAL"){
    (abs($days_left) eq 1) and $plural="" or $plural="s";
    if($days_left < 0){
        $status = "CRITICAL";
        $days_left = abs($days_left);
        $msg .= "Certificate EXPIRED $days_left day$plural ago for '$domain'. Expiry Date: '$end_date'";
    } else { 
        $msg .= "$days_left day$plural remaining for '$domain'. Certificate Expires: '$end_date'";
        $msg .= " (w=$warning/c=$critical days)" if $verbose;
        if($days_left <= $critical){
            $status = "CRITICAL";
        }elsif($days_left <= $warning){
            $status = "WARNING";
        }
    }
}

($san_names_checked eq 1) and $plural="" or $plural="s";
if($san_names_checked){
    $msg .= " [$san_names_checked SAN name$plural checked]";
}
quit "$status", "$msg";
