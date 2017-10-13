#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-05-24 10:38:54 +0100 (Tue, 24 May 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Nginx stats. Nginx will need to be configured to support this, see documentation at http://wiki.nginx.org/HttpStubStatusModule

Tested on Nginx circa 2010/2011 and more recently version 1.9.11, 1.10.0, 1.11.0";

$VERSION = "0.5.0";

use strict;
use warnings;
use Fcntl ':flock';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use LWP::UserAgent;
use POSIX;

set_port_default(80);

env_creds('Nginx');

my $conns_sec;
my $contents;
my $diff_secs;
my $last_accepted = 0;
my $last_active = 0;
my $last_handled;
my $last_reading;
my $last_requests = 0;
my $last_tstamp   = 0;
my $last_waiting;
my $last_writing;
my $no_keepalives = 0;
my $requests_sec;
my $state_file_empty = 0;
my $url;

%options = (
    %hostoptions,
    "u|url=s"          => [ \$url,           "Nginx Status URL (usually something like /nginx_status - must be compiled with support and enabled in the nginx config using stub_status)" ],
    "no-keepalives"    => [ \$no_keepalives, "Use only when nginx config has 'keepalive_timeout 0' to enable an extra sanity check against the Handled/Request counts where Handled >= Requests must be true. A sanity check of Accepted >= Handled is performed regardless" ],
    "w|warning=s"      => [ \$warning,       "Warning  threshold or ran:ge (inclusive) for Active Connections count" ],
    "c|critical=s"     => [ \$critical,      "Critical threshold or ran:ge (inclusive) for Active Connections count" ],
);

@usage_order = qw/host port url no-keepalives warning critical/;

get_options();

$host = validate_host($host);
$host = validate_resolvable($host);
$port = validate_port($port);
$url  = validate_url_path_suffix($url, "nginx stub");
$url  =~ s/^\///;
$url  = "http://$host:$port/$url";
$url  = validate_url($url, "full");

validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 1, "positive" => 1 } );
vlog2;

set_timeout();

my $statefh;
my $statefile = "/tmp/$progname.$host.tmp";
my $state_file_existed = 0;
if(-f $statefile){
    $state_file_existed = 1;
    vlog2 "opening state file '$statefile'\n";
    open $statefh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
} else {
    vlog2 "creating state file '$statefile'\n";
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
            vlog2 "state file is empty";
        } else {
            vlog2 "checking state file against regex: '$state_regex'\n";
            $contents =~ /$state_regex/ or quit "UNKNOWN", "Error: state file '$statefile' was not in the expected format, offending line was \"$_\"";
            $last_tstamp   = $1;
            $last_active   = $2;
            $last_reading  = $3;
            $last_writing  = $4;
            $last_waiting  = $5;
            $last_accepted = $6;
            $last_handled  = $7;
            $last_requests = $8;
            vlog2 "last active:   $last_active";
            vlog2 "last reading:  $last_reading";
            vlog2 "last writing:  $last_writing";
            vlog2 "last waiting:  $last_waiting";
            vlog2 "last accepted: $last_accepted";
            vlog2 "last_handled:  $last_handled";
            vlog2 "last requests: $last_requests";
        }
    } else {
        $state_file_empty = 1;
        vlog2 "state file is empty";
    }
}

my $now  = time;
if($last_tstamp > 0 and $last_tstamp < $now){
    # we have a last state and there is no time funniness
    $diff_secs = $now - $last_tstamp;
} else {
    $diff_secs = 0;
}
vlog2 "$diff_secs secs since last run\n";

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");
validate_resolvable($host);
my $req = HTTP::Request->new(GET => $url);

#my $time = strftime("%F %T", localtime);
vlog2 "sending request";
my $res  = $ua->request($req);
vlog2 "got response";
my $status_line  = $res->status_line;
vlog2 "status line: $status_line";
my $content = my $content_single_line = $res->content;
vlog3 "\ncontent:\n\n$content\n";
$content_single_line =~ s/\n/ /g;
sub not_found {
    quit "CRITICAL", "cannot find '@_' in output => '$content_single_line' from '$url'";
}

unless($res->code eq 200){
    quit "CRITICAL", "'$status_line'";
}
if($content =~ /\A\s*\Z/){
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
vlog2 "\nperforming sanity check on returned stats: Accepted >= Handled\n";
unless($accepted >= $handled){
    quit "CRITICAL", "handled connection count > accepted connection count, sanity check failed on nginx stats returned by server!";
}
if($no_keepalives){
    vlog2 "performing extra sanity check on returned stats: Handled >= Requests\n";
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
    vlog2 "not updating state file since 0 secs since last run\n";
}

print $statefh "$now $active $reading $writing $waiting $accepted $handled $requests" if ($diff_secs > 0 or $state_file_empty or not $state_file_existed);

$status = "OK";

$msg = "Active connections = $active";
check_thresholds($active);
$msg .= ", Connections / sec = $conns_sec, Requests / sec = $requests_sec, Reading = $reading, Writing = $writing, Accepted = $accepted, Handled = $handled, Requests = $requests";
$msg .= " | 'Active connections'=$active;" . (defined($thresholds{warning}{upper}) ? $thresholds{warning}{upper} : "") . ";" . (defined($thresholds{critical}{upper}) ? $thresholds{critical}{upper} : "") . ";0; 'Connections / sec'=$conns_sec 'Requests / sec'=$requests_sec 'Reading'=$reading 'Writing'=$writing 'Accepted'=$accepted 'Handled'=$handled 'Requests'=$requests";

quit $status, $msg;
