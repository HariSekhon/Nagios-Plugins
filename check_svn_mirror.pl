#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2010-11-11 11:44:32 +0000 (Thu, 11 Nov 2010)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Subversion mirror/slave is up to date compared to it's master";

$VERSION = "0.4";

use warnings;
use strict;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $master_url;
my $slave_url;
my $max_rev_lag = 0;
$user           = "";
$password       = "";

env_creds("SVN");

%options = (
    "M|master-url=s"  => [ \$master_url,  "Master SVN url (the url to the master svn server)" ],
    "S|slave-url=s"   => [ \$slave_url,   "Slave/Mirror SVN url (run this from the mirror svn server as eu ops backup mirror is only accessible to localhost)" ],
    "m|max-rev-lag=i" => [ \$max_rev_lag, "Maximum revisions the mirror is allowed to be behind the master (defaults to 0, min 0, max 50)" ],
    %useroptions,
);
@usage_order = qw/master-url slave-url max-rev-lag user password/;

get_options();

$master_url  = validate_url($master_url, "master");
$slave_url   = validate_url($slave_url,  "slave/mirror");
$max_rev_lag = validate_int($max_rev_lag, "max revision lag", 0, 50);
if($user){
    $user = validate_user($user);
    $user = " --username=$user";
}
if($password){
    $password = validate_password($password);
    $password = " --password=$password";
}

vlog2 "Master URL:       $master_url";
vlog2 "Slave/Mirror URL: $slave_url";
vlog2 "Max Revision Lag: $max_rev_lag\n";

set_timeout($timeout, sub{ pkill("^svn info ", "-9") } );

sub get_revision {
    my $rev;
    my @errors = ();
    my @output = cmd("exec svn info --non-interactive --no-auth-cache$user$password $_[0]");
    foreach(@output){
        if (/svn: PROPFIND request failed on|svn: Server sent unexpected return value|Host not found|could not connect to server|error|failed|PROPFIND|Forbidden/i){
            push(@errors, $_);
        }
        next if (not /^Revision: (\d+)$/);
        $rev = $1;
    }
    quit "UNKNOWN", join(",", @errors) if(@errors);
    isInt($rev) or quit "UNKNOWN", "Failed to get revision for '$_[0]'";
    return $rev;
}

my $master_revision = get_revision $master_url;
vlog3;
my $slave_revision = get_revision $slave_url;

defined($master_revision) or quit "UNKNOWN", "Failed to get master revision from '$master_url'";
defined($slave_revision)  or quit "UNKNOWN", "Failed to get slave/mirror revision from '$slave_url'";
isInt($master_revision) or quit "UNKNOWN", "Failed to get master revision from '$master_url' - result '$master_revision' is not an integer";
isInt($slave_revision)  or quit "UNKNOWN", "Failed to get slave revision from '$slave_url' - result '$slave_revision' is not an integer";

vlog2 "master revision: $master_revision";
vlog2 "slave  revision: $slave_revision";

my $revision_lag = $master_revision - $slave_revision;

my $msg = "$revision_lag revisions behind master. Master Rev: $master_revision, Slave Rev: $slave_revision | 'Revision Lag'=$revision_lag;$max_rev_lag;$max_rev_lag";

if ($slave_revision eq $master_revision or $revision_lag <= $max_rev_lag) {
    $status = "OK";
}
else {
    critical;
}
quit $status, $msg;
