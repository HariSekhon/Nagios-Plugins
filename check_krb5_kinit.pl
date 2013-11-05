#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-05 00:26:27 +0000 (Tue, 05 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check Kerberos is working by getting a TGT from the KDC using a keytab

Create a nagios kerberos principal and export a keytab for it to use in this check

Requirements:

1. Kerberos KDC(s)
2. /etc/krb5.conf
3. nagios kerberos principal
4. exported keytab for the nagios kerberos principal
";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use File::Temp 'tempfile';

my $default_principal = "nagios";
my $principal = $default_principal;
my $keytab;

%options = (
    "p|principal=s"    => [ \$principal,    "Kerberos principal to use (default: $default_principal)" ],
    "k|keytab=s"       => [ \$keytab,       "Path to Keytab exported containing principal credentials. Required" ],
);

@usage_order = qw/principal keytab/;
get_options();

$principal = validate_krb5_princ($principal);
$keytab    = validate_file($keytab, undef, "keytab");
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

vlog2 "creating temporary ticket cache";
# the destructor of this object should clean up this temp file for us
my $fh = File::Temp->new(TEMPLATE => "/tmp/${progname}_krb5cc_$>_XXXXXX");
my $ticket_cache = $fh->filename;
vlog2 "temporary ticket cache is '$ticket_cache'\n";

vlog2 "requesting TGT";
my @output = cmd("kinit -c '$ticket_cache' -k -t '$keytab' '$principal'");
if(@output){
    quit "CRITICAL", join(" ", @output);
}

vlog2 "validating TGT\n";
@output = cmd("klist -c '$ticket_cache'");
foreach(@output){
    next if(
    /^Ticket\s+cache:\s+FILE:$ticket_cache\s*$/i or
    /^Default\s+principal:\s+$principal(?:(?:\/$domain_regex)?\@$domain_regex)?\s*$/i    or
    /^\s*$/ or
    /^Valid\s+starting\s+Expires\s+Service principal\s*$/i or
    /^\s*renew until/i
    );
    /(\d{2}\/\d{2}\/\d{2}\s+\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2}\s+\d{2}:\d{2}:\d{2})\s+krbtgt\/$domain_regex\@$domain_regex/i or quit "CRITICAL", "unrecognized line: '$_'. $nagios_plugins_support_msg";
    if($1 eq $2){
        quit "CRITICAL", "TGT start and expiry are the same";
    }
}

$msg = "$principal TGT validated";

quit $status, $msg;
