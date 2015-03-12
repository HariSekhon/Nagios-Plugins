#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-08-11 17:12:01 +0000 (Wed, 11 Aug 2010)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check SSL Certificate Validity

Checks:

1. Certificate Expiry in days
2. Chain of Trust
   2a. Root CA certificate is trusted
   2b. Any intermediate certificates are present, especially important for Mobile devices
3. Domain name on certificate (optional)
4. Subject Alternative Names supported by certificate (optional)
5. SNI - Server Name Identification - supply hostname identifier for servers that contain multiple certificates to tell the server which SSL certificate to use (optional)";

$VERSION = "0.9.10";

use warnings;
use strict;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use POSIX 'floor';

my $openssl          = "/usr/bin/openssl";
$port                = 443;
my $default_critical = 15;
my $default_warning  = 31;

$critical            = $default_critical;
$warning             = $default_warning;

my $CApath;
my $cmd;
my $domain;
my $sni_hostname;
my $end_date;
my $expected_domain;
my $no_validate;
# Worked on OpenSSL 0.98.x on RHEL5 and Mac OS X 10.6-10.9
#my $openssl_output_for_shell_regex = '[\w\s_:=@\*,\/\.\(\)\n+-]+';
# OpenSSL 1.0.x on RHEL6 outputs session tickets and prints hex which can include single quotes, and quotemeta breaks certificate interpretation so not using this now
#my $openssl_output_for_shell_regex = qr/^[\w\s\_\:\;\=\@\*\.\,\/\(\)\{\}\<\>\[\]\r\n\#\^\$\&\%\~\|\\\!\"\`\+\-]+$/; # will be single quoted, don't allow single quotes in here
my @subject_alt_names;
my $subject_alt_names;
my $verify_code = "";
my $verify_msg  = "";
my @output;

%options = (
    "H|host=s"                      => [ \$host,                "SSL host to check" ],
    "P|port=s"                      => [ \$port,                "SSL port to check (defaults to port 443)" ],
    "d|domain=s"                    => [ \$expected_domain,     "Expected domain/FQDN registered to the certificate" ],
    "s|subject-alternative-names=s" => [ \$subject_alt_names,   "Additional FQDNs to require on the certificate (optional)" ],
    "S|SNI-hostname=s"              => [ \$sni_hostname,        "SNI hostname to tell a server with multiple certificates which one to use (eg. www.domain2.com, optional)" ],
    "w|warning=s"                   => [ \$warning,             "The warning threshold in days before expiry (defaults to $default_warning)" ],
    "c|critical=s"                  => [ \$critical,            "The critical threshold in days before expiry (defaults to $default_critical)" ],
    "C|CApath=s"                    => [ \$CApath,              "Path to ssl root certs dir (will attempt to determine from openssl binary if not supplied)" ],
    "N|no-validate"                 => [ \$no_validate,         "Do not validate the SSL certificate chain" ]
);
@usage_order = qw/host port domain subject-alternative-names SNI-hostname warning critical CApath no-validate/;

get_options();

$host   = validate_host($host);
$port   = validate_port($port);
$CApath = validate_dir($CApath, 0, "CA path") if defined($CApath);
$sni_hostname = validate_hostname($sni_hostname, "SNI") if $sni_hostname;
validate_thresholds(1, 1, { "simple" => "lower", "integer" => 0, "positive" => 1 } );

if($expected_domain){
    # Allow wildcard certs
    if(substr($expected_domain, 0 , 2) eq '*.'){
        $expected_domain = "*." . validate_domain(substr($expected_domain, 2));
    } else {
        $expected_domain = validate_domain($expected_domain);
    }
}

if($subject_alt_names){
    @subject_alt_names = split(",", $subject_alt_names);
    foreach(@subject_alt_names){
        validate_domain($_);
    }
}

vlog2;

# pkill is available on Linux but not MAC by default, hence using pkill subroutine from my utils instead for portability
set_timeout($timeout, sub { pkill("$openssl s_client -connect $host:$port", "-9") } );

$openssl = which($openssl, 1);

unless(defined($CApath)){
    @output = cmd("$openssl version -a");
    foreach(@output){
        if (/^OPENSSLDIR: "($filename_regex)"\s*\n?$/) {
            $CApath = $1;
            vlog2 "Found CApath from openssl binary as: $CApath\n";
            last;
        }
    }
    unless(defined($CApath)){
        usage "CApath to root certs was not specified and could not be found from openssl binary";
    }
    $CApath = validate_dir($CApath, 0, "CA path");
}

vlog2;

$status = "OK";

vlog2 "* checking validity of cert (chain of trust)";
$cmd = "echo | $openssl s_client -connect $host:$port -CApath $CApath";
$cmd .= " -servername $sni_hostname" if $sni_hostname;
$cmd .= " 2>&1";

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
($verify_code ne "") or quit "UNKNOWN", "Certificate validation failed - failed to find verify code in openssl output - failed to get certificate correctly or possible code error. $nagios_plugins_support_msg";
$verify_code =~ s/,\s*$//;
$verify_msg  =~ s/,\s*$//;
vlog2 "Verify return code: $verify_code ($verify_msg)\n";

if (not $no_validate and $verify_code ne 0){
    # Don't handle expiry as part of the cert chain, we want nicer output with more details later
    if(not ( $verify_code eq 10 and $verify_msg =~ /certificate has expired/ ) ){
        quit "CRITICAL", "Certificate validation failed, returned $verify_code ($verify_msg)";
    }
}

#my $output = join("\n", @output);
# This breaks session tickets which have an ascii dump of any char and seems to have changed recently on Linux
#$output =~ /^($openssl_output_for_shell_regex)$/ or die "Error: unexpected/illegal chars in openssl output, refused to pass to shell for safety\n";
#$output = $1;
# This breaks the certificate input
#$output = quotemeta($output);

vlog2 "* checking domain and expiry on cert";
#$cmd = "echo '$output' | $openssl x509 -noout -enddate -subject 2>&1";
#$cmd = "echo '$output' | $openssl x509 -noout -text 2>&1";

# Avoiding the IPC stuff as blocking is a problem, using extra openssl fetch, not ideal but a better fix than the alternatives
# Could write this to a temporary file to avoid 1 round-trip but would need to be extremely robust and would break on things like /tmp filling up, this is a better trade off as is
$cmd .= " | $openssl x509 -noout -text 2>&1";
@output = cmd($cmd);

foreach (@output){
    #if (/notAfter\=/) {
    if (/Not After\s*:\s*(\w+\s+\d+\s+\d+:\d+:\d+\s+\d+\s+\w+)/) {
        $end_date  = $1;
        #defined($end_date) || quit "CRITICAL", "failed to determine certificate expiry date";
    }
    #elsif (/subject=/) {
    # The * must be in there for wildcard certs
    elsif (/Subject:(?:.+,)?\s*CN=([\*\w\.-]+)/) {
        $domain = $1;
        #defined($domain) || quit "CRITICAL", "failed to determine certificate domain name";
        last;
    }
}

sub is_cert_domain ($) {
    my $domain = shift;
    if($domain =~ /^\*\./){
        $domain =~ s/^\*\.//;
    }
    isFqdn($domain) or isDomain($domain);
}

defined($domain)   or quit "CRITICAL", "failed to determine certificate domain name";
defined($end_date) or quit "CRITICAL", "failed to determine certificate expiry date";
vlog2 "Domain: $domain";
vlog2 "Certificate Expires: $end_date\n";
is_cert_domain($domain) or quit "UNKNOWN", "unrecognized domain certficate returned. $nagios_plugins_support_msg";

my ($month, $day, $time, $year, $tz) = split(/\s+/, $end_date);
my ($hour, $min, $sec)               = split(/\:/, $time);

my $days_left = floor( timecomponents2days($year, $month, $day, $hour, $min, $sec) );
isInt($days_left, 1) or code_error "non-integer returned for days left calculation. $nagios_plugins_support_msg";

vlog2 "* checking expected domain name on cert\n";
if ($expected_domain and $domain ne $expected_domain) {
    critical;
    $msg .= "domain '$domain' did not match expected domain '$expected_domain'! ";
}

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
            critical;
        }
    }
    if(scalar @missing_alt_names){
        plural scalar @missing_alt_names;
        $msg .= scalar @missing_alt_names . " SAN name$plural missing: " . join(",", @missing_alt_names) . ".";
    }
    vlog2;
}

if(!is_critical){
    plural abs($days_left);
    if($days_left < 0){
        critical;
        $days_left = abs($days_left);
        $msg .= "Certificate EXPIRED $days_left day$plural ago for '$domain'. Expiry Date: '$end_date'";
    } else { 
        $msg .= "$days_left day$plural remaining for '$domain'. Certificate Expires: '$end_date'";
        check_thresholds($days_left);
    }
}

plural $san_names_checked;
if($san_names_checked){
    $msg .= " [$san_names_checked SAN name$plural checked]";
}
quit $status, $msg;
