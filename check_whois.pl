#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-04-12 11:29:56 +0100 (Thu, 12 Apr 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check domain expiry via whois lookup

This is an important piece of code given that ppl overlook domain renewals till the last minute (and auto-renewals fail when their cached credit cards have expired)

Uses jwhois command - path to jwhois command can be specified manually otherwise searches for 'jwhois' (as on Ubuntu) or if not found then tries 'whois' (as on CentOS/RHEL) in /bin & /usr/bin


Checks:

* checks days left if given thresholds
* checks domain status
* checks DNS servers
* checks for other optional details where available
* lots of sanity checking on output
* optionally validates the following details if expected results specified:
  - admin email
  - tech email
  - nameservers list
  - registrant
  - registrar

I have used this in production for nearly 800 domains across a great variety of over 100 TLDs/second-level domains last I checked, including:

ac, ag, am, asia, asia, at, at, be, biz, biz, ca, cc, cc, ch, cl, cn, co, co.at, co.il, co.in, co.kr, co.nz, co.nz, co.uk, co.uk, com, com, com.au, com.au, com.bo, com.br, com.cn, com.ee, com.hk, com.hk, com.mx, com.mx, com.my, com.pe, com.pl, com.pt, com.sg, com.sg, com.tr, com.tw, com.tw, com.ve, de, dk, dk, eu, fi, fm, fm, fr, gs, guru, hk, hu, idv.tw, ie, in, info, info, io, it, jp, jp, kr, london, lu, me, me.uk, mobi, mobi, ms, mx, mx, my, name, net, net, net.au, net.br, net.cn, net.nz, nf, nl, no, nu, org, org, org.cn, org.nz, org.tw, org.uk, org.uk, pl, ru, se, sg, sg, sh, tc, tel, tel, tl, tm, tv, tv.br, tw, us, us, vg, xxx

DISCLAIMER:

1. TLDs can change/revoke whois info at any time, so this code will need updating should such occasions arise
2. some TLDs for some small countries don't even have whois servers, this is handled in code where I know of it to state such
3. I recommend you run the latest version of jwhois that you can get, I've found a scenario where older jwhois on Debian Wheezy didn't return expiry information for google.name compared to the version on CentOS
";

# For developing/testing on Mac I've found this has worked:
#
# brew install homebrew/boneyard/jwhois
#
# Update: this doens't seem to work any more, now gives below error for any domain, even though version is the same as on Linux :-/
#
# [Querying whois.verisign-grs.com]
# [Unable to connect to remote host]

# Whois perl libraries aren't great so calling whois binary and checking manually
# so we have more control over this, can get sticky but it looks like this is the reason
# there isn't a universal whois lib for perl!

# Wow all the variations have been horrid for parsing all this info. No wonder there is no lib for this

# Not the most beautiful piece of code I ever wrote but still more extensive than anything out
# there esp thanks to the leveraging of my Nagios lib

# WARNING: DO NOT EDIT THIS PLUGIN, A SIMPLE CHANGE CAN RADICALLY ALTER THE LOGIC AND DATE PARSING/MANIPULATIONS
# GIVING A FALSE SENSE OF SECURITY, SAME GOES FOR THE TESTS ACCOMPANYING IT, CHECK WITH HARI SEKHON FIRST
# THERE IS A LOT OF REGEX. EVEN IF YOU ARE A REGEX MASTER YOU CANNOT PREDICT ALL SIDE EFFECTS
# YOU MUST RELY ON THE ACCOMPANYING TESTS I HAVE WRITTEN IF YOU CHANGE ANYTHING AT ALL

$VERSION = "0.11.6";

use strict;
use warnings;
use Time::HiRes 'time';
use Time::Local;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

my $domain;
my $whois;
my $whois_server;
my %expected_results;
my $no_expiry = 0;
my $no_nameservers = 0;
my $default_whois_server_asia = "whois.nic.asia";
my $default_whois_server_tel = "whois.nic.tel";
my $default_warning  = 60;
my $default_critical = 30;
$warning  = $default_warning;
$critical = $default_critical;

# These will use $whois_server = whois.nic.$tld
my @tld_alt_whois = qw/asia bo fm me ms nf tel xxx/;
my %tld_alt_whois = (
    "pe" => "kero.yachay.pe",
    #"vn" => "whois.iana.org"
    );

my @tlds_with_no_expiry      = qw/at be ch de hu eu lu name nl no pe/;
my @tlds_with_no_nameservers = qw/ac sh/;

%options = (
    "d|domain=s"       => [ \$domain,           "Domain to check" ],
    "C|jwhois-path=s"  => [ \$whois,            "jwhois command's full path (optional, searches for 'jwhois' or 'whois' in /bin & /usr/bin)" ],
    "H|whois-server=s" => [ \$whois_server,     "Query this specific whois server host" ],
    "w|warning=s"      => [ \$warning,          "Warning threshold in days for domain expiry (defaults to $default_warning days)"  ],
    "c|critical=s"     => [ \$critical,         "Critical threshold in days for domain expiry (defaults to $default_critical days)" ],
    "no-expiry"        => [ \$no_expiry,        "Do not check expiry. Do not use this except for those rubbish broken european TLDs whois like .fr" ],
    "no-nameservers"   => [ \$no_nameservers,   "Do not check for nameservers. You should not use this normally" ],
    "name-servers=s"   => [ \$expected_results{"nameservers"}, "Name servers to expect for domain, should be comma delimited list, no spaces"   ],
    "registrant=s"     => [ \$expected_results{"registrant"},  "Registrant to expect"  ],
    "registrar=s"      => [ \$expected_results{"registrar"},   "Registrar to expect"   ],
    "admin-email=s"    => [ \$expected_results{"admin_email"}, "Admin email to expect" ],
    "tech-email=s"     => [ \$expected_results{"tech_email"},  "Tech email to expect"  ]
);

@usage_order = qw/domain jwhois-path whois-server warning critical no-expiry no-nameservers name-servers registrant registrar admin-email tech-email/;
get_options();

$domain = lc validate_domain($domain);
my $tld = $domain;
$tld =~ s/.*\.//o;
# TODO: HTTP scrape this using the web form
my @tlds_without_whois_servers = qw/ar es gr ph pk py vn/;
quit "UNKNOWN", ".ph domain lookups are not available to the public as of Apr-2012, must manually go to http://www.dot.ph/whois/ and pass captcha" if $tld eq "ph";
if(grep($tld eq $_, @tlds_without_whois_servers)){
    quit "UNKNOWN", ".$tld domain lookups are not available at this time";
}
unless($whois_server){
    if(grep($_ eq $tld, @tld_alt_whois)){
        $whois_server = "whois.nic.$tld";
    } elsif(grep($_ eq $tld, keys %tld_alt_whois)){
        $whois_server = $tld_alt_whois{$tld};
    }
    #if($tld eq "asia"){
    #    $whois_server = $default_whois_server_asia;
    #} elsif($tld eq "tel"){
    #    $whois_server = $default_whois_server_tel;
    #}
    vlog2("changing whois server to '$whois_server'") if $whois_server;
}
if($whois_server){
    $whois_server = isHost($whois_server) || usage "invalid whois server given";
}
validate_thresholds(undef, undef, { "simple" => "lower", "positive" => 1 } );
vlog2;

# This will actually interfere with other calls if it ever goes wrong but better than
# allowing zombies
set_timeout($timeout, sub { pkill("whois") } );
if($whois){
    $whois = validate_program_path($whois, "jwhois", "j?whois");
} else {
    $whois = which("jwhois") || which("whois", 1);
}
my @output = cmd("$whois");
unless($output[0] =~ /^jwhois\s+/){
    quit "UNKNOWN", "wrong whois version detected, please install/specify path to GNU jwhois";
}

my $cmd = "$whois -d $domain";
$cmd    = "$whois -d -h $whois_server $domain" if $whois_server;
set_timeout($timeout, sub { pkill("$cmd") } );

$status = "OK";
my $start  = time;
@output = cmd("$cmd");
my $stop   = time;
my $total_time = sprintf("%.4f", $stop - $start);
vlog2("whois query returned in $total_time secs\n");
my $perfdata = " | whois_query_time=${total_time}s";

my %results;

my %mon = (
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
);

my $not_registered_msg = "domain '$domain' not registered!!!";
if($domain =~ /^www/){
    $not_registered_msg .= " Did you accidentally specify the FQDN? Try removing 'www' from the beginning?";
}
my $expiry_not_checked_msg = "EXPIRY NOT CHECKED for domain $domain,";

my @dns_servers;
@{$results{"status"}} = ();

# https://www.icann.org/resources/pages/epp-status-codes-2014-06-16-en
# statuses we don't want to accept:
#                       inactive
#                       pendingCreate
#                       pendingDelete
#                       pendingRestore
#                       redemptionPeriod
#                       serverHold
#                       serverRenewProhibited
my @valid_statuses = qw/
                        Active
                        ACTIVO
                        addPeriod
                        AUTORENEWPERIOD
                        CLIENT-DELETE-PROHIBITED
                        CLIENT-RENEW-PROHIBITED
                        CLIENT-UPDATE-PROHIBITED
                        CLIENT-XFER-PROHIBITED
                        clientDeleteProhibited
                        clientRenewProhibited
                        clientTransferProhibited
                        clientUpdateProhibited
                        Complete
                        connect
                        Delegated
                        Granted
                        HOLD
                        ok
                        pendingRenew
                        pendingTransfer
                        pendingUpdate
                        published
                        Publicado
                        registered
                        RENEWPERIOD
                        serverDeleteProhibited
                        serverTransferProhibited
                        serverUpdateProhibited
                        TRANSFERPERIOD
                        VERIFIED
                        VerifiedID
                        /;
# add valid statuses with spaces in them
push(@valid_statuses,
    (
        "200 Active",
        "auto-renew grace",
        "CLIENT DELETE PROHIBITED",
        "CLIENT RENEW PROHIBITED",
        "CLIENT TRANSFER PROHIBITED",
        "CLIENT UPDATE PROHIBITED",
        "DELETE PROHIBITED",
        "NOT AVAILABLE",
        "NOT DELEGATED",
        "paid and in zone",
        "Registered until expiry date",
        "SERVER UPDATE PROHIBITED",
        "Transfer Allowed",
        "Transfer Locked",
        "TRANSFER PROHIBITED",
        "UPDATE PROHIBITED"
    )
);
my @not_registered_statuses = qw/free/;
push(@not_registered_statuses, "Not Registered");
# regex valid statuses
my @valid_statuses2 = (
    "Registered until renewal date.?"
);
foreach(@valid_statuses2){
    validate_regex($_, "status", 1) or code_error "invalid regex '$_' in \@valid_statuses";
}
sub valid_status {
    my $status = shift;
    #vlog2("* checking status: $status");
    if($status =~ /,/){
        foreach my $status_part (split(",", $status)){
            if(grep(lc($_) eq lc($status_part), @valid_statuses)){
                return 1;
            }
        }
    } elsif(grep(lc($_) eq lc($status), @valid_statuses)){
        return 1;
    } else {
        foreach(@valid_statuses2){
            $status =~ /^$_$/ and return 1;
        }
    }
    return 0;
}

my ($day, $month, $year);
if($tld eq "ar"){
    my $domain_found = 0;
    foreach(@output){
        if(/\b$domain\b/){
            $domain_found = 1;
            last;
        }
    }
    quit "CRITICAL", $not_registered_msg unless $domain_found;
} elsif($tld eq "tm"){
    foreach(@output){
        if(/^Domain "$domain" - Not available\s*$/io){
            #quit "OK", "$domain domain registered. No further info available from whois. See http://www.nic.tm/ for more information";
            $msg = "$domain domain registered. No further info available from whois. See http://www.nic.tm/ for more information. ";
            $results{"domain"} = $domain;
            $no_expiry = 1;
            @dns_servers = ( "N/A" );
            last;
        }
    }
}

my %domain_mismatches;
foreach(@output){
    if(/\[.*Unable to connect to remote host.*\]/io or
       /\[.*Name or service not known.*\]/io or
       /(?:daily whois-limit exceeded for client (?:$ip_regex)?|too many requests|Look up quota exceeded|exceeded.+query.+limit|WHOIS LIMIT EXCEEDED)/io or
       /^query_status:\s+[13-9]\d{2}\s+/io or
       /^\s*Invalid input\s*$/io or
       /quota exceeded/io or
       /Unable to locate remote host/io or
       /Unable to connect/io or
       /Can't access/io or
       /No Data Found/o
        ){
        quit "UNKNOWN", "error while checking domain '$domain': " . strip($_);
    } elsif(/No entries found|NOT FOUND|No match/io   or
            /Status:\s+AVAILABLE/io                   or
            /(?:$domain).+(?<!Not )\b(?:free|available)\b/io or
            /Domain Available.+$domain/io             or
            /The domain has not been registered/io    or
            /query_status: 220 Available/io
        ){
        quit "CRITICAL", $not_registered_msg;
    # UK Nominet Errors, either cos of violating naming or "Nominet not the registry for" etc
    } elsif(/Error for /io){
        quit "CRITICAL", "Error for domain $domain returned, see full whois output for details";
    } elsif(/^\s*Domain Expiration Date:\s+\w{3}\s+(\w{3})\s+(\d{1,2})\s+\d{1,2}:\d{1,2}:\d{1,2}\s+\w{3}\s+(\d{4})\s*$/io) {
        ($day, $month, $year) = ($2, $1, $3);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/^\s*Expires on\b\.*:\s*(\d{4})-([A-Za-z]{3})-(\d{1,2}).?\s*$/io or
            /^(?:Expiration Date|paid-till)\s*:\s*(\d{4})(?:\.|-) ?(\d{2})(?:\.|-) ?(\d{2})\.?\s*/io) {
        ($day, $month, $year) = ($3, $2, $1);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/(?:expir.+?|Renewal)(?: Date)?:?\s*(\d{1,2})[-\. \/]([a-z]+)[-\. \/](\d{4}|\d{2})(?:\.|\s+\d{1,2}:\d{1,2}(?::\d{1,2})?(?: \w{3})?)?\s*$/io){
        ($day, $month, $year) = ($1, $2, $3);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/(?:expir.+?|Renewal)(?: Date)?:?\s*(\d{4})[-\.\/](\d{1,2})[-\.\/](\d{1,2})\.?(?:\s+\d{1,2}:\d{1,2}:\d{1,2})?\s*$/io){
        ($year, $month, $day) = ($1, $2, $3);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/(?:expir.+?|Renewal|validity)(?: Date)?:?\s*(\d{1,2})[-\.\/](\d{1,2})[-\.\/](\d{4})\.?\s*$/io){
        ($day, $month, $year) = ($1, $2, $3);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/(?:expir.+?|Renewal)(?: Date)?:?\s*(\d{1,2})[-\.\/](\d{1,2})[-\.\/](\d{2})\.?\s*$/io or
            /^\s*Record expires on (\d{4})-(\d{2})-(\d{2})\s+\(YYYY-MM-DD\)\s*$/io or
            /^\s*Fecha de Vencimiento:\s+(\d{4})-(\d{2})-(\d{2})(?:\s+\d{2}:\d{2}:\d{2})?\s*$/io){
        ($day, $month, $year) = ($3, $2, $1);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/^expires:?\s*(\d{4})(\d{2})(\d{2})\s*$/io){
        ($day, $month, $year) = ($3, $2, $1);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/^\s*Expires\s*:\s*(\w+)\s+(\d{1,2})\s+(\d{4})\s*\.\s*$/io or
            /^\s*Expires on\.+:\s*\w{3},\s+(\w{3})\s+(\d{1,2}),\s+(\d{4})\s*$/io){
        ($day, $month, $year) = ($2, $1, $3);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    } elsif(/^domain_datebilleduntil:\s+(\d{4})-(\d{2})-(\d{2})T\d{1,2}:\d{1,2}:\d{1,2}\+\d{1,2}:\d{1,2}\s+$/o){
        ($day, $month, $year) = ($3, $2, $1);
        $results{"expiry"} = "$day-$month-$year";
        vlog2("Expiry: $results{expiry}");
    # GoDaddy registration dates eg. 'Registrar Registration Expiration Date: 2015-09-02T16:50:03Z'
    } elsif(/\b(?:Expiration|Registry Expiry|Registrar Registration Expiration|Expires On)(?:\s+Date)?.*?(\d{4})-(\d{2})-(\d{2})(?:[^\d]|$)/io){
        ($day, $month, $year) = ($3, $2, $1);
        $results{"expiry"} = "$day-$month-$year";
    } elsif (/^\s*(?:Query:|Domain(?:[ _]?Name)?\s*(?:\(ASCII\))?[.:]+)\s*(.+?)\s*$/io or
             /^(?:[a-z]?\s)?\[Domain Name\]\s+(.+?)\s*$/o or
             /^Nome de [^\s]+\s*\/\s*Domain Name:\s*($domain_regex_strict)\s*$/io or
             /^\s*Nombre de Dominio:\s*($domain_regex_strict)\s*$/io or
             /^Dominio:\s*($domain_regex_strict)/io or
             /^Domain\s+\"?($domain_regex_strict)\"?/io or
             /^ACE:\s($domain_regex_strict)\s/
             ){
        if($results{"domain"}){
            unless($results{"domain"} eq $1){
                $domain_mismatches{$results{"domain"}} = 1;
                $domain_mismatches{$1} = 1;
            }
        }
        $results{"domain"} = $1;
        vlog2("Domain Name: $results{domain}");
        # checking domain further down which accounts for EU peculiarity
        #lc($results{"domain"}) eq lc($domain) or quit "CRITICAL", "whois mismatch - returned domain '$results{domain}' instead of '$domain'";
    } elsif (/(?:Name ?Server|nserver|ns_name_\d{1,2})s?.*?(?:$hostname_regex\s+NS\s+)?($fqdn_regex|$ip_regex)\.?(\s+.+)?\s*$/io or
             /(?:prim|sec)ns\d?fqdn\s*:\s*($fqdn_regex)\s*$/io){
        my $nameserver = $1;
        $nameserver =~ s/\.$//;
        isFqdn($nameserver) or isIP($nameserver) or quit "CRITICAL", "name server '$nameserver' returned by whois lookup is not a valid hostname or ip address!!! Check '$domain' domain name servers are working properly!";
        push(@dns_servers, lc($nameserver)) unless(grep(lc($_) eq lc($nameserver), @dns_servers));
    } elsif (/^(?:[a-z]\s)?\s*\[?(?:Domain(?: Name)?|Record)?\s*(?:Creat.*?|Regist[a-z]+|Commencement) ?(?:Date|on)?\]?:?\s*(\d+[-\.\/](?:\d+|\w+)[-\.\/]\d+)/io){
        $results{"created"} = $1;
    } elsif (/^\s*Domain Registration Date:\s+\w{3}\s+(\w{3})\s+(\d{1,2})\s+\d{1,2}:\d{1,2}:\d{1,2}\s+\w{3}\s+(\d{4})\s*$/io or
             /^\s*Created on\.+:\s+\w{3},\s+(\w{3})\s+(\d{1,2}),\s+(\d{4})$/o or
             /^\s*Created\s*:\s*(\w+)\s+(\d{1,2})\s+(\d{4})\.?\s*$/io){
        $results{"created"} = "$2-$1-$3";
    } elsif(/^created:?\s*(\d{4})(\d{2})(\d{2})\s*$/io or
            /^Registered Date\s+:\s+(\d{4})\.\s+(\d{2})\.\s+(\d{2})\.$/io or
            /^\s*Fecha de (?:Creacion|registro):\s+(\d{4})-(\d{2})-(\d{2})(?:\s+\d{2}:\d{2}:\d{2})?\s*$/o or
            /^domain_dateregistered:\s+(\d{4})-(\d{2})-(\d{2})T\d{1,2}:\d{1,2}:\d{1,2}\+\d{1,2}:\d{1,2}\s*$/o){
        $results{"created"} = "$3-$2-$1";
    } elsif(/^Created:?\s*(\d{1,2}) (\w{3}) (\d{4}) \d{1,2}:\d{1,2} \w{3}\s*$/io or
            /^Created:\s*(\d{1,2})\s+([a-z]{3})\s+(\d{4})\s*$/io){
        $results{"created"} = "$1-$2-$3";
    } elsif (/(?:Updat.+?|Modified|Changed):?\s*(\d+[-\.\/](?:\d+|\w+)[-\.\/]\d+)/io or
             /^(?:[a-z]\s)?\[Record Last Modified\]\s+(.+?)\s*$/){
        next if /Last update of WHOIS database/i;
        $results{"updated"} = $1;
    } elsif (/^\s*Domain Last Updated Date:\s+\w{3}\s+(\w{3})\s+(\d{1,2})\s+\d{1,2}:\d{1,2}:\d{1,2}\s+\w{3}\s+(\d{4})\s*$/io or
             /^\s*Last Updated\s*:\s*(\w+)\s+(\d{1,2})\s+(\d{4})\.?\s*$/io or
             /^\s*Record last updated on\.+:\s+\w{3},\s+(\w{3})\s+(\d{1,2}),\s+(\d{4})$/o){
        $results{"updated"} = "$2-$1-$3";
    } elsif(/^changed:?\s*(\d{4})(\d{2})(\d{2})\s*$/io or
            /^Last updated Date\s+:\s+(\d{4})\.\s+(\d{2})\.\s+(\d{2})\.$/io or
            /^\s*Ultima Actualizacion:\s*(\d{4})-(\d{2})-(\d{2})\s+\d{2}:\d{2}:\d{2}\s*$/ ){
        $results{"updated"} = "$3-$2-$1";
    } elsif(/^Modified:?\s*(\d{1,2}) (\w{3}) (\d{4}) \d{1,2}:\d{1,2} \w{3}\s*$/io or
            /^Modified:\s*(\d{1,2})\s+([a-z]{3})\s+(\d{4})\s*$/io){
        $results{"updated"} = "$1-$2-$3";
    } elsif (/(?:status|domaintype):\s*(\w[\w\s-]+\w)/io or
             /\[Status\]\s+(.+?)\s*$/o or
             /^\s*Estatus del dominio:\s*(.+?)\s*$/){
        my $domain_status = strip($1);
        $domain_status =~ s/\s+https?$//i;
        $domain_status =~ s/\s+--.*$//i;
        $domain_status =~ s/ -//;
        push(@{$results{"status"}}, $domain_status);
    } elsif (/^state:\s*([\w\s,-]+)\s*$/io){
        my @states = split(",", $1);
        foreach(@states){
            my $domain_status = strip($1);
            $domain_status =~ s/ -//;
            push(@{$results{"status"}}, $domain_status);
        }
    } elsif (/^\s*(?:Registrant Organization|Organisation Name|registrant_contact_name)[.:]+\s*(.+?)\s*$/io or
             /^\[Registrant\]\s+(.+?)\s*$/ or
             /^Registrant\s*:\s+(.+?)\s*$/ or
             /^org-name:\s+(.+?)\s*$/){
        $results{"registrant"} = $1;
        #$results{"registrant"} =~ s/(, (?:LLC|Inc|Ltd))?\.?\s*$//io;
    } elsif (/(?:registrar(?:[ _]name)?|Registered through):\s*(.+?)\s*$/io){
        $results{"registrar"} = $1;
        #$results{"registrar"} =~ s/, Ltd\.? .+$//io;
    } elsif (/^\s*(?:Admin Email|admin_contact_email|Administrative Contact Email)[.:]+\s*($email_regex)\s*$/io){
        $results{"admin_email"} = $1;
    } elsif (/^\s*(?:Tech Email|technical_contact_email|Technical Contact Email)[.:]+\s*($email_regex)\s*$/io){
        $results{"tech_email"} = $1;
    }
}

#use Data::Dumper;
#debug("dns servers:" . Dumper(@dns_servers) . "\n");
my $no_nameservers_listed = 0;
foreach(my $i=0;$i<scalar @output;$i++){
    my $line = $output[$i];
    if($line =~ /^\s*Domain name:?\s*$/io
        # for Estonia EE registrar eg. myspace.com.ee
            or $line =~ /^\s*Domain:\s*$/io
        ){
        $output[$i+1] or last;
        $line = $output[$i+1] or code_error "hit end of output";
        if($line =~ /($domain_regex_strict)/o){
            $results{"domain"} = $1;
        }
    } elsif($line =~ /^\s*Registrar:?\s*$/io){
        $output[$i+1] or last;
        $line = $output[$i+1] or code_error "hit end of output";
        $results{"registrar"} = $line or code_error "hit end of output";
        $results{"registrar"} =~ s/^\s*(?:.+?:|.+:)?\s*//o;
        $results{"registrar"} =~ s/\.?\s*(?:\[\s*Tag\s*=\s*.+\])?\s*$//io;
    } elsif($line =~ /^\s*\**\s*Registrant(?:\s+Contact Information)?:?\s*$/io or
            $line =~ /^Holder of domain name:/o or
            $line =~ /^\s*Titular:\s*$/){
        if($output[$i+1] =~ /^\s*$/){
            $output[$i+2] or last;
            $i++;
        }
        $line = $output[$i+1] or code_error "hit end of output";
        $results{"registrant"} = $line or code_error "hit end of output";
        $results{"registrant"} =~ s/^\s*(?:.+?:|.+:)?\s*//o;
        $results{"registrant"} =~ s/\s*$//o;
    } elsif($line =~ /^\s*Domain Information\s*$/io){
        my $j = $i + 2;
        while($j<scalar @output){
            $output[$j] or last;
            $line = $output[$j] or code_error "hit end of output";
            if($line =~ /^\s*Organization Name\s*:\s*(.+?)\s*$/){
                $results{"registrant"} = $1 unless $results{"registrant"};
                last;
            }
            $j++;
        }
    } elsif($line =~ /^\s*(?:Admin(?:\.|istrative)? Contact|\[Zone-C\]|Contacto Administrativo)(?:\s+Information)?:?\s*$/io){
        my $j=$i+1;
        while(1){
            $output[$j] or last;
            $line = $output[$j] or code_error "hit end of output";
            if($line =~ /($email_regex)/o){
                $results{"admin_email"} = $1;
            }
            $j++;
        }
    } elsif($line =~/^\s*(?:Technical Contact(?:, Zone Contact)?|\[Tech-C\]|Contacto Tecnico)(?:\s+Information)?:?\s*$/io){
        my $j=$i+1;
        while(1){
            $output[$j] or last;
            $line = $output[$j] or code_error "hit end of output";
            if($line =~ /($email_regex)/o){
                $results{"tech_email"} = $1;
            }
            $j++;
        }
    } elsif($line =~/^\s*Administrative Contact, Technical Contact(?:\s+Information)?:?\s*$/io){
        $output[$i+1] or last;
        $line = $output[$i+1] or code_error "hit end of output";
        if($line =~ /($email_regex)/o){
            $results{"admin_email"} = $1;
            $results{"tech_email"}  = $1;
        }
    } elsif($line =~/^\s*(?:Registration\s+)?status:?\s*$/io){
        $output[$i+1] or last;
        $line = $output[$i+1] or code_error "hit end of output";
        $line = strip($line);
        $line =~ s/\.$//;
        push(@{$results{"status"}}, strip($line));
    } elsif( ( (!@dns_servers) and
               ($line =~ /^\s*\**\s*(?:Primary |Secondary )?(?:DNS|Domain|Name) ?(?:name ?)?servers?.*:?\s*$/io or
                $line =~ /^Servidores de nombre \(Domain servers\):/o) or
                $line =~ /Resource Records \(\d+\):\s*$/o or
                $line =~ /^\s*Servidor\(es\) de Nombres de Dominio:\s*$/o
             ) or
             $line =~ /^\s*[a-z]\s+\[(?:Primary|Secondary) Name Server\]\s+(?:\w+)?\s*$/o
             #$line =~ /^\s*Name Servers:\s*$/o
        ){
        foreach(my $j=$i+1;$j<scalar @output;$j++){
            defined($output[$j]) or last;
            my $line2 = $output[$j];
            $line2 =~ s/^\s*(.+?:)?\s*//o;
            $line2 =~ s/\s*$//o;
            if($line2 =~ /^\s*$/o){
                if($output[$j+1]){
                    last if $output[$j+1] =~ /^\s*$/o;
                    last unless $output[$j+1] =~ /$fqdn_regex|$ip_regex/o;
                }
                next;
            }
            if($line2 =~ /No name servers listed/io){
                unless($no_nameservers){
                    critical;
                    $msg = "NO NAME SERVERS LISTED. $msg";
                }
                $no_nameservers_listed = 1;
                last;
            } else {
                # exclusion for EU domains since there isn't
                # another idea that works for EU domains but this might match match genuine multiple nameservers eg:
                # nameserver1 nameserver2 nameserver3 nameserver4 on a line from one of the many registrars so not risking it
                #next if (scalar split(/\s+/, $line2) > 5);
                next if ($line2 =~ /\b(?:Please|visit|for|more|info)\b/i);
                foreach my $nameserver (split(/\s+/, $line2)){
                    next if(lc $nameserver eq "ns");
                    if(isFqdn($nameserver) or isIP($nameserver)){
                        push(@dns_servers, lc($nameserver)) unless(grep($_ eq lc($nameserver), @dns_servers));
                    }
                }
            }
        }
    }
}

foreach(@not_registered_statuses){
    foreach my $status (@{$results{"status"}}){
        (lc($status) eq lc($_)) and quit "CRITICAL", $not_registered_msg;
    }
}

my $whois_server_responded = "";
foreach(@output){
    if(/\[($fqdn_regex)\]/){
        $whois_server_responded = $1;
    }
}

my $holder;
unless($results{"registrant"}){
    foreach(@output){
        if(/^person:\s*(.+?)\s*$/){
            $results{"registrant"} = $1;
        }
    }
}
if($results{"registrant"}){
    $results{"registrant"} =~ s/\(.*$//;
    $results{"registrant"} =~ s/(,?\s*(?:LLC|Inc|Ltd|S\.?A\.?S?))?\.?\s*$//io;
}
if($results{"registrar"}){
    $results{"registrar"} =~ s/,?\s*(?:LLC|Inc|Ltd|S\.?A\.?S?|(?:Ltd )?R\d+-ASIA)?\.?(?:\s+\((?:[\w-]+|http:\/\/$hostname_regex)\))?\.?\s*$//io;
} else {
    foreach(@output){
        if (/^\[Querying\s+(?:http:\/\/)?($domain_regex_strict)(?:$url_path_suffix_regex)?\]$/){
            $results{"registrar"} = $1;
            $results{"registrar"} =~ s/(?:www|whois)\.//o;
        }
    }
}
# This is for .fr
unless($results{"registrant"}){
    foreach(my $i=0;$i<scalar @output;$i++){
        if($output[$i] =~ /^holder-c:\s+(.+?)\s*$/){
            $holder = $1;
        } elsif($holder and $output[$i] =~ /^nic-hdl:\s+$holder\s*$/){
            foreach(my $j=$i;$j<scalar @output;$j++){
                if($output[$j] =~ /^contact:\s+(.+)\s*$/){
                    $results{"registrant"} = $1;
                    last;
                }
            }
            last;
        }
    }
}

if($results{"registrar"} eq "markmonitor.com" and not defined($results{"expiry"}) ){
    foreach(@output){
        /^\[(?:Querying|Redirected)? ?$fqdn_regex\]|\s*$/ or quit "UNKNOWN", "Unknown output found from MarkMonitor registrar: '$_'";
    }
    # MarkMonitor doesn't give any output when it's a registered domain
    quit "OK", "MarkMonitor registrar gives no details but domain is currently registered $perfdata";
}

my $anti_automation = 0;
if (not $results{"expiry"}){
    if($no_expiry){
        $msg = "${msg}${expiry_not_checked_msg}";
    } elsif(grep($_ eq $tld, @tlds_with_no_expiry)){
        vlog2("Excepting domain $domain from expiry check as we can't find the expiry and it's a .$tld domain");
        $msg = "${msg}${expiry_not_checked_msg}";
        $msg =~ s/,$//;
        $msg .= " due to .$tld registrar not supporting it,";
        $no_expiry = 1;
    } elsif($results{"registrar"} =~ /GoDaddy/io){
        $msg = "${msg}GODADDY ${expiry_not_checked_msg}";
        $msg =~ s/, $//;
        $msg .= " (anti-automation output)";
        $anti_automation = 1;
        $no_expiry = 1;
    } elsif($whois_server_responded eq "whois.ausregistry.net.au"){
        $msg = "${msg}whois.ausregistry.net.au ${expiry_not_checked_msg}";
        $no_expiry = 1;
    }
} elsif($no_expiry){
    $msg = "${msg}${expiry_not_checked_msg}";
}
unless($no_expiry){
    if($results{"expiry"}){
        if($month !~ /^\d+$/){
            $month = substr(lc($month),0,3);
            grep($_ eq $month, (keys %mon)) or quit "UNKNOWN", "didn't understand returned month '$month', couldn't convert to usable format";
            $month = $mon{$month};
        }
        # Months start from zero with our lib, so decrement by 1
        $month--;
        defined($month)   and
        $month =~ /^\d+$/ and
        $month >= 0       and
        $month <= 11
            or code_error "failed to convert month to numeric equivalent";
        $results{"expiry_epoch"} = timegm(0,0,0,$day,$month,$year);
        vlog2("expiry_epoch epoch: $results{expiry_epoch}");
    } else {
        if(defined($results{"domain"})){
            quit "UNKNOWN", "expiry not found in output from whois $domain (use -vvv to check output, some registrars don't supply it in which case you may need to use --no-expiry switch)";
        }
        quit "UNKNOWN", "neither domain nor expiry found in output for whois $domain, domain not registered? Use -vvv to check output, registrars output may have changed. $nagios_plugins_support_msg";
    }
    $results{"expiry_epoch"} or quit "UNKNOWN", "couldn't calculate expiry epoch from expiry '$results{expiry}' in output from whois $domain";
}

vlog2;
foreach(sort keys %results){
    next if $_ eq "status";
    vlog2("$_: '$results{$_}'");
}
foreach(@{$results{"status"}}){
    vlog2("status: '$_'");
}
foreach(@dns_servers){
    vlog2("name server: '$_'");
    if($_ eq $domain){
        warning;
        $msg = "Nameserver matches domain!!! $msg";
    }
}
foreach(qw/registrar created updated/){
    vlog2("\nWARNING: missing $_\n") unless $results{$_};
}
vlog2("\nWARNING: missing status\n") unless ($results{"status"} and scalar @{$results{"status"}});

my $days_left="UNKNOWN";
unless($no_expiry){
    $days_left = sprintf("%d", ( $results{"expiry_epoch"} - time() ) / 86400);
    $msg = "${msg}${days_left} days left for $domain domain, expires '$results{expiry}'";
    #vlog2("* checking days thresholds");
    check_thresholds($days_left);
}

if(grep(lc $_ eq lc $tld, @tlds_with_no_nameservers)){
    vlog2("excepting $domain from nameserver checks as it's a $tld tld");
    $no_nameservers = 1;
}
if($no_nameservers){
    unless(@dns_servers){
        $no_nameservers_listed = 1;
    }
}

my @invalid_statuses = ();
if(@{$results{"status"}}){
    foreach my $domain_status (@{$results{"status"}}){
        unless(valid_status($domain_status)){
            $domain_status =~ s/\.$//;
            push(@invalid_statuses, $domain_status);
        }
    }
}
if(@invalid_statuses){
    $msg = "invalid status '". join(",", @invalid_statuses) . "' found! $msg";
    warning;
}
my @not_found;
if($tld eq "hu"){
    push(@dns_servers, "N/A_in_HU");
}
unless($no_nameservers_listed){
    #push(@not_found, "nameservers") unless @dns_servers;
    unless (@dns_servers) {
        warning;
        $msg = "No nameservers found. $msg";
    }
}
#unless($results{"domain"}){
#    if($tld eq "cl"){
#        my $domain_minus_tld = $domain;
#        $domain_minus_tld =~ s/\.[^\.]+$//;
#        foreach(@output){
#            if(/http:\/\/www\.nic\.cl\/cgi-bin\/dom-CL\?q=$domain_minus_tld/o){
#                $results{"domain"} = $domain;
#            }
#        }
#    }
#}
# Registrant and updated aren't output by all whois servers
foreach my $result (("expiry", "domain")){
    next if ($no_expiry   and $result eq "expiry");
    next if ($tld eq "tr" and $result eq "domain");
    unless($results{$result} and $results{$result} !~ /^\s*$/){
        push(@not_found, $result);
    }
}
if(@not_found){
    warning;
    my $msg2 = join("/", sort @not_found) . " not found in whois output";
    if(grep { $_ eq "domain" } @not_found){
        critical;
        $msg2 .= " (domain not registered?)";
    }
    $msg = "$msg2. $msg";
}

if($results{"registrant"} and $results{"registrant"} eq ""){
    code_error "registrant is empty";
}

my @nameservers;
my @results_mismatch;
if($expected_results{"nameservers"}){
    #vlog2("* checking nameservers");
    @nameservers = split(",", $expected_results{"nameservers"});
    foreach my $returned_nameserver (@dns_servers){
        unless(grep(lc($_) eq lc($returned_nameserver), @nameservers)){
            push(@results_mismatch, "nameservers") unless grep("nameservers", @results_mismatch);
        }
    }
    foreach my $expected_nameserver (@nameservers){
        unless(grep(lc($_) eq lc($expected_nameserver), @dns_servers)){
            push(@results_mismatch, "nameservers") unless grep("nameservers", @results_mismatch);
        }
    }
}

if($results{"domain"}){
    # For some reason eu returns without .eu
    if ($tld eq "eu"){
        $results{"domain"} .= ".eu" unless $results{"domain"} =~ /\.eu$/;
    }
    unless(lc($results{"domain"}) eq lc($domain)){
        warning;
        $msg = "domain mismatch!!! (expected '$domain', got '$results{domain}') $msg";
    }
    if(%domain_mismatches){
        warning;
        $msg = sprintf("mismatching domain found multiple (%d) times in registrar output: %s - raise a ticket on github for a fix https://github.com/harisekhon/nagios-plugins/issues. %s", scalar keys %domain_mismatches,  join(" vs ", sort keys %domain_mismatches), $msg);
    }
}
my @not_found_expected;
foreach(qw/registrant registrar admin_email tech_email/){
    if($expected_results{$_}){
        if($results{$_}){
            if(lc($expected_results{$_}) ne lc($results{$_}) ){
                vlog2("* checking $_");
                push(@results_mismatch, $_);
            }
        } else {
            next if ($anti_automation and substr($_, -5) eq "email");
            push(@not_found_expected, $_);
            next;
        }
    }
}
if(@not_found_expected){
    warning;
    $msg = "couldn't find " . join("/", @not_found_expected) . " yet expected result was specified. $msg";
}

if(@results_mismatch){
    warning;
    $msg = "whois mismatch on expected " . join("/", @results_mismatch) . " results. $msg";
}

unless($no_expiry){
    if($days_left < 1){
        critical;
        $msg = "$domain domain EXPIRED!!! $msg";
    }
}

if($verbose){
    $msg .= " nameservers:";
    if($no_nameservers_listed){
        $msg .= "NONE";
    } else {
        if(@dns_servers){
            $msg .= join(",", @dns_servers);
        } else {
            $msg .= "NOT_FOUND";
        }
    }
    unless($results{"registrar"}){
        $results{"registrar"} = "UNKNOWN";
    }
    $msg .= " (expected: " . join(",", @nameservers) . ")" if (grep($_ eq "nameservers", @results_mismatch));
    $msg .= " registrant:'$results{registrant}'" if $results{"registrant"};
    $msg .= " (expected: $expected_results{registrant})" if (grep($_ eq "registrant", @results_mismatch));
    $msg .= " registrar:'$results{registrar}'" ;#if $results{"registrar"};
    $msg .= " (expected: $expected_results{registrar})" if (grep($_ eq "registrar", @results_mismatch));
    $msg .= " created:$results{created}" if $results{"created"};
    $msg .= " updated:$results{updated}" if $results{"updated"};
    $msg .= " admin_email:'" . $results{"admin_email"} . "'" if $results{"admin_email"};
    $msg .= " (expected: $expected_results{admin_email})" if (grep($_ eq "admin_email", @results_mismatch));
    $msg .= " tech_email:'"  . $results{"tech_email"}  . "'" if $results{"tech_email"};
    $msg .= " (expected: $expected_results{tech_email})" if (grep($_ eq "tech_email", @results_mismatch));
} else {
    $msg =~ s/,$//;
}
$msg .= $perfdata;

my $extended_command = dirname $progname;
$extended_command .= "/$progname -vd $domain";
$extended_command .= " --no-expiry" if $no_expiry;
$extended_command .= " --no-nameservers" if $no_nameservers;
$extended_command .= " --name-servers=" . join(",", @dns_servers) if @dns_servers;
$extended_command .= " --registrant=\"$results{registrant}\""   if $results{"registrant"};
$extended_command .= " --registrar=\"$results{registrar}\""     if $results{"registrar"};
$extended_command .= " --admin-email=\"$results{admin_email}\"" if $results{"admin_email"};
$extended_command .= " --tech-email=\"$results{tech_email}\""   if $results{"tech_email"};
$extended_command .= " --timeout=$timeout"   if($timeout ne $timeout_default);

vlog2;
vlog3("\nextended command: $extended_command\n\n");
quit $status, $msg;
