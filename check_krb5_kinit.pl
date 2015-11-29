#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-05 00:26:27 +0000 (Tue, 05 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

our $DESCRIPTION = "Nagios Plugin to check Kerberos is working for the local system by getting a TGT from any available configured KDC using a keytab

To test a specific KDC instead use the check_krb5_kdc.pl symlink to this plugin which changes the mode

Create a nagios kerberos principal and export a keytab for it to use in this check

Requirements:

- Kerberos KDC
- /etc/krb5.conf
- nagios kerberos principal
- exported keytab for the nagios kerberos principal
- kinit command in standard system path
";

$VERSION = "0.4.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use File::Temp;

my $default_principal = "nagios";
my $principal         = $default_principal;
my $keytab;

my $conf;
my $kdc;
my $realm;
my $renewable;

set_port_default(88);

env_creds("KDC");

%options = (
    "k|keytab=s"       => [ \$keytab,       "Path to Keytab exported containing principal credentials" ],
    "p|principal=s"    => [ \$principal,    "Kerberos principal to use (default: $default_principal)" ],
    "C|conf=s"         => [ \$conf,         "Path to krb5.conf (optional, usually defaults to /etc/krb5.conf)" ],
    "r|renewable"      => [ \$renewable,    "Checks we are able to retrieve a renewable TGT (optional)" ],
);
@usage_order = qw/host port realm keytab principal conf renewable/;

if($progname eq "check_krb5_kdc.pl"){
    $kdc = 1;
    $DESCRIPTION =~ s/check Kerberos is working.*KDC/check a specific Kerberos KDC is working by getting a TGT/;
    $DESCRIPTION =~ s/To test a specific KDC.*\n\n//;
    $DESCRIPTION =~ s/- \/etc\/krb5.conf/- Kerberos Realm/;
    delete $options{"C|conf=s"};
    %options = (
        %hostoptions,
        "R|realm=s" => [ \$realm, "Kerberos Realm" ],
        %options,
    );
}

get_options();

if($kdc){
    $host  = validate_host($host);
    $port  = validate_port($port);
    $realm = validate_krb5_realm($realm);
}
$keytab    = validate_file($keytab, "keytab");
$principal = validate_krb5_princ($principal);
if($conf){
    $conf      = validate_file($conf, "conf");
    $conf =~ /(?:.*\/)?krb5.conf$/ or usage "must specify a file called krb5.conf if using --conf";
}

vlog2;
set_timeout();

$status = "OK";

vlog2 "creating temporary ticket cache";
# the destructor of this object should clean up this temp file for us
my $fh = File::Temp->new(TEMPLATE => "/tmp/${progname}_krb5cc_$>_XXXXXXXXXX");
my $ticket_cache = $fh->filename;
vlog2 "temporary ticket cache is '$ticket_cache'\n";

my $fh2;
if($host){
    vlog2 "creating temporary krb5.conf configuration file";
    $fh2 = File::Temp->new(TEMPLATE => "/tmp/${progname}.krb5.conf.XXXXXXXXXX");
    my $conf_tmp = $fh2->filename;
    vlog2 "writing conf '$conf_tmp' for realm '$realm' with kdc '$host:$port'";
    print $fh2 "
[libdefaults]
    default_realm = $realm
[realms]
    $realm = {
        kdc = $host:$port
    }
";
    close $fh2;
    $conf = $conf_tmp;
    vlog2;
    validate_resolvable($host);
}

if($conf){
    vlog2 "setting krb5.conf configuration file to '$conf'\n";
    $ENV{"KRB5_CONFIG"} = $conf;
}

vlog2 "requesting TGT";
my $cmd = "kinit -c '$ticket_cache' -k -t '$keytab' '$principal'";
if($renewable){
    $cmd .= " -r 1d";
}
my @output = cmd($cmd);
if(@output){
    if($output[0] =~ /Keytab contains no suitable keys/){
        $output[0] .= " (did you generate the keytab correctly and specify the correct principal and realm including correct capitalisation?)";
    } elsif($output[0] =~ /Cannot contact any KDC/){
        $output[0] .= " (KDC down or specified incorrect --host/--port?)";
    }
    quit "CRITICAL", join(" ", @output);
}

vlog2 "validating TGT\n";
@output = cmd("klist -c '$ticket_cache'");
foreach(@output){
    next if(
    # Ticket on Linux, Credentials on Mac
    /^(?:Credentials|Ticket)?\s+cache:\s+FILE:$ticket_cache\s*$/i or
    # Default on Linux, no prefix on Mac
    /^(?:Default)?\s+principal:\s+$principal(?:(?:\/$hostname_regex)?\@$domain_regex)?\s*$/i or
    /^\s*$/ or
    /^Valid\s+starting\s+Expires\s+Service principal\s*$/i or
    /^\s*Issued\s+Expires\s+Principal\s*$/i or
    /^\s*renew until/i
    );
    /(\d{2}\/\d{2}\/\d{2,4}\s+\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2,4}\s+\d{2}:\d{2}:\d{2})\s+krbtgt\/$domain_regex\@$domain_regex/i or
    /(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+krbtgt\/$domain_regex\@$domain_regex/i
        or quit "CRITICAL", "unrecognized line: '$_'. $nagios_plugins_support_msg";
    if($1 eq $2){
        quit "CRITICAL", "TGT start and expiry are the same (misconfiguration of the kerberos principal '$principal' in the KDC while requesting renewable ticket?)";
    }
}

$msg = "Kerberos TGT validated for principal '$principal'";
$msg .= " with keytab '$keytab'" if $verbose;

quit $status, $msg;
