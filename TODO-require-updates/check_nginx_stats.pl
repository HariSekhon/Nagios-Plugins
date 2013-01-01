#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-05-24 10:38:54 +0100 (Tue, 24 May 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# TODO: reintegrate this with HariSekhonUtils

$main::VERSION = "0.3.1";

use strict;
use warnings;
use Fcntl ':flock';
use Getopt::Long qw(:config bundling);
use LWP::UserAgent;
use POSIX;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use utils qw(%ERRORS $TIMEOUT);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

my $conns_sec;
my $contents;
my $critical;
my $default_port = 80;
my $default_timeout = 10;
my $diff_secs;
my $help;
my $host;
my $last_accepted = 0;
my $last_active = 0;
my $last_handled;
my $last_reading;
my $last_requests = 0;
my $last_tstamp   = 0;
my $last_waiting;
my $last_writing;
my $no_keepalives = 0;
my $port = $default_port;
my $requests_sec;
my $state_file_empty = 0;
my $timeout = $default_timeout;
my $url;
my $verbose = 0;
my $version;
my $warning;

sub quit{
    print "$_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

my $progname = basename $0; 
$progname =~ /^([\w_\.-]+)$/ or die "script name was invalid\n";
$progname = $1;

sub usage{
    print "@_\n" if defined(@_);
    print "usage: $progname -H host [ -p port ] -u '/nginx_status' -w <warning_threshold> -c <critical_threshold> [ -t secs -v ]

--host     -H    Host to connect to
--port     -p    Port to connect to (defaults to $default_port)
--url      -u    Nginx Status URL (usually something like /nginx_status - must be compiled with support and enabled on the nginx config)
--warning  -w    The warning threshold for Active Connections
--critical -c    The critical threshold for Active Connections
--no-keepalives  Use only when nginx config has 'keepalive_timeout 0' to enable an extra sanity check against the Handled/Request counts where Handled >= Requests must be true. A sanity check of Accepted >= Handled is performed regardless
--timeout  -t    Timeout in seconds (defaults to $default_timeout, min 1, max 60)
--version  -V    Show version and exit
--verbose  -v    Verbose mode
--help     -h    Print this help
\n";
    exit $ERRORS{"UNKNOWN"};
}

sub vlog{
    print "@_\n" if $verbose;
}

GetOptions (
            "h|help|usage"       => \$help,
            "H|host=s"           => \$host,
            "p|port=i"           => \$port,
            "u|url=s"            => \$url,
            "w|warning=i"        => \$warning,
            "c|critical=i"       => \$critical,
            "t|timeout=i"        => \$timeout,
            "no-keepalives"      => \$no_keepalives,
            "v|verbose+"         => \$verbose,
            "V|version"          => \$version,
           ) or usage "invalid option specified";

usage if defined($help);
die "$progname Version $main::VERSION\n" if defined($version);

defined($host)                  || usage "hostname not specified";
$host =~ /^([\w\.-]+)$/         || die "invalid hostname given\n";
$host = $1;

defined($port)                  || usage "port not specified";
$port  =~ /^(\d+)$/             || die "invalid port number given, must be a positive integer\n";
$port = $1;
($port >= 1 && $port <= 65535)  || die "invalid port number given, must be between 1-65535)\n";

defined($url) or usage "url is not specified";
$url =~ /^(\/?[\w\.\;\=\&\%\/-]+)$/ or die "Invalid URL given\n";
$url = $1;

defined($warning)       || usage "warning threshold not defined";
defined($critical)      || usage "critical threshold not defined";
$warning  =~ /^(\d+)$/  || usage "invalid warning threshold given, must be a positive numeric integer";
$warning = $1;
$critical =~ /^(\d+)$/  || usage "invalid critical threshold given, must be a positive numeric integer";
$critical = $1;
($critical >= $warning) || usage "critical threshold must be greater than or equal to the warning threshold";

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || die "timeout value must 1 - 60 secs\n";

$SIG{ALRM} = sub {
    quit "UNKNOWN", "check timed out after $timeout seconds";
};
vlog "verbose mode on";
vlog "setting plugin timeout to $timeout secs\n";
alarm($timeout);

my $statefh;
my $statefile = "/tmp/$progname.$host.tmp";
my $state_file_existed = 0;
if(-f $statefile){
    $state_file_existed = 1;
    vlog "opening state file '$statefile'\n";
    open $statefh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
} else {
    vlog "creating state file '$statefile'\n";
    open $statefh, "+>$statefile" or quit "UNKNOWN", "Error: failed to create state file '$statefile': $!";
}
flock($statefh, LOCK_EX | LOCK_NB) or quit "UNKNOWN", "Failed to aquire a lock on state file '$statefile', another instance of this plugin was running?";

my $state_regex = '^(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$';
if($state_file_existed == 1){
    $contents = <$statefh>;
    if ($contents){
        chomp $contents;
        if($contents =~ /^\s+$/){
            $state_file_empty = 1;
            vlog "state file is empty";
        } else {
            vlog "checking state file against regex: '$state_regex'\n";
            $contents =~ /$state_regex/ or quit "UNKNOWN", "Error: state file '$statefile' was not in the expected format, offending line was \"$_\"";
            $last_tstamp   = $1;
            $last_active   = $2;
            $last_reading  = $3;
            $last_writing  = $4;
            $last_waiting  = $5;
            $last_accepted = $6;
            $last_handled  = $7;
            $last_requests = $8;
            vlog "last active:   $last_active";
            vlog "last reading:  $last_reading";
            vlog "last writing:  $last_writing";
            vlog "last waiting:  $last_waiting";
            vlog "last accepted: $last_accepted";
            vlog "last_handled:  $last_handled";
            vlog "last requests: $last_requests";
        }
    } else {
        $state_file_empty = 1;
        vlog "state file is empty";
    }
}

my $now  = time;
if($last_tstamp > 0 and $last_tstamp < $now){
    # we have a last state and there is no time funniness
    $diff_secs = $now - $last_tstamp;
} else {
    $diff_secs = 0;
}
vlog "$diff_secs secs since last run\n";
$url =~ s/^\///;
$url = "http://$host:$port/$url";

vlog "Host: $host";
vlog "Port: $port";
vlog "Full URL: $url\n";

my $ua = LWP::UserAgent->new;
$ua->agent("$progname/$main::VERSION ");
my $req = HTTP::Request->new(GET => $url);

#my $time = strftime("%F %T", localtime);
vlog "sending request";
my $res  = $ua->request($req);
vlog "got response";
my $status  = my $status_line  = $res->status_line;
$status  =~ s/\s.*$//;
if($status !~ /^\d+$/){
    quit "UNKNOWN", "CODE ERROR - status code '$status' is not a number (status line was: '$status_line')";
}
vlog "status line: $status_line";
my $content = my $content_single_line = $res->content;
vlog "\ncontent:\n\n$content\n";
$content_single_line =~ s/\n/ /g;
sub not_found {
    quit "CRITICAL", "cannot find '@_' in output => '$content_single_line' from '$url'";
}

unless($status eq 200){
    quit "CRITICAL", "'$status_line'";
}
if($content =~ /^\s*$/){
    quit "CRITICAL", "empty body returned from '$url'";
}
unless($content =~ /Active connections:\s+(\d+)/){
    not_found "Active connections";
}
my $active = $1;
unless($content =~ /server accepts handled requests\n\s+(\d+)\s+(\d+)\s+(\d+)/){
    not_found "server accepts handled requests";
}
my $accepted = $1;
my $handled  = $2;
my $requests = $3;
# Sanity checks
vlog "performing sanity check on returned stats: Accepted >= Handled";
unless($accepted >= $handled){
    quit "CRITICAL", "handled connection count > accepted connection count, sanity check failed on nginx stats returned by server!";
}
if($no_keepalives){
    vlog "performing extra sanity check on returned stats: Handled >= Requests";
    unless($handled >= $requests){
        quit "CRITICAL", "request count > handled connection count, sanity check failed on nginx stats returned by server!";
    }
}
unless($content =~ /Reading:\s+(\d+)\s+Writing:\s+(\d+)\s+Waiting:\s+(\d+)/){
    not_found "Reading/Writing/Waiting";
}
my $reading = $1;
my $writing = $2;
my $waiting = $3;
if(not $state_file_existed or $accepted < $last_accepted or $diff_secs == 0){
    # This means nginx either:
    # 1. There is no state
    # 2. Nginx has been restart and the counters reset
    # 3. Not enough time has elapsed between runs of this plugin
    $conns_sec    = "N/A";
    $requests_sec = "N/A";
} else {
    $conns_sec    = int( ($accepted - $last_accepted) / $diff_secs );
    $requests_sec = int( ($requests - $last_requests) / $diff_secs );
}

if($diff_secs > 0){
    seek($statefh, 0, 0)  or quit "UNKNOWN", "Error: seek failed on '$statefile': $!";
    truncate($statefh, 0) or quit "UNKNOWN", "Error: failed to truncate '$statefile': $!";
} else {
    vlog "not updating state file since 0 secs since last run\n";
}

print $statefh "$now $active $reading $writing $waiting $accepted $handled $requests" if ($diff_secs > 0 or $state_file_empty or not $state_file_existed);

my $msg = my $msg2 = "'Active connections' = $active;$warning;$critical, 'Connections / sec' = $conns_sec, 'Requests / sec' = $requests_sec, 'Reading' = $reading, 'Writing' = $writing, 'Accepted' = $accepted, 'Handled' = $handled, 'Requests' = $requests";
$msg =~ s/'//g;
$msg =~ s/;(\d+);(\d+)/ (w=$1\/c=$2)/g;
$msg2 =~ s/,//g;
$msg2 =~ s/\s*=\s*/=/g;
$msg .= "| $msg2";

$status = "OK";
if($active >= $critical){
    $status = "CRITICAL";
} elsif($active >= $warning) {
    $status = "WARNING";
}

quit($status, $msg);
