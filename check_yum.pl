#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Rewrite  Date: 2012-12-30 13:02:35 +0000 (Sun, 30 Dec 2012)
#  Original Date: 2008-04-29 17:21:08 +0100 (Tue, 29 Apr 2008)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Yum security updates on RHEL5/6/7 based servers

This is a rewrite of my original Python version for RHEL5 from early 2008

Code is much shorter, a third the number of lines, and leverages my personal library for better validation, option/usage and self timeout handling

See also: check_yum.py (the original, also part of the Advanced Nagios Plugins Collection)

Tested on CentOS 5 / 6 / 7
";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

set_timeout_max(3600);

my $YUM = "/usr/bin/yum";

my $all_updates;
my $warn_on_any_update;
my $cache_only;
my $no_warn_on_lock;
my $enablerepo;
my $disablerepo;

%options = (
    "A|all-updates"         =>  [ \$all_updates,        "Does not distinguish between security and non-security updates, but returns critical for any available update. This may be used if the yum security plugin is absent or you want to maintain every single package at the latest version. You may want to use --warn-on-any-update instead of this option" ],
    "W|warn-on-any-update"  =>  [ \$warn_on_any_update, "Warns if there are any (non-security) package updates available. By default only warns when security related updates are available. If --all-updates is used, then this option is redundant as --all-updates will return a critical result on any available update, whereas using this switch still allows you to differentiate between the severity of updates" ],
    "C|cache-only"          => [ \$cache_only,          "Run entirely from cache and do not update the cache when running yum. Useful if you have 'yum makecache' cronned so that the nagios check itself doesn't have to do it, possibly speeding up execution (by 1-2 seconds in tests)" ],
    "N|no-warn-on-lock"     => [ \$no_warn_on_lock,     "Return OK instead of WARNING when yum is locked and fails to check for updates due to another instance running. This is not recommended from the security standpoint, but may be wanted to reduce the number of alerts that may intermittently pop up when someone is running yum for package management" ],
    "e|enablerepo=s"        => [ \$enablerepo,          "Explicitly enables  a repository when calling yum. Can take a comma separated list of repositories" ],
    "d|disablerepo=s"       => [ \$disablerepo,         "Explicitly disables a repository when calling yum. Can take a comma separated list of repositories" ],
);

@usage_order = qw/all-updates warn-on-any-update cache-only no-warn-on-lock enablerepo disablerepo/;

get_options();

linux_only();

my $opts = "";
$opts .= "-C" if $cache_only;

sub validate_reponame($){
    my $repo = shift;
    $repo =~ /^(\w+[\w\.-]*\w+)$/ or usage "invalid repo name '$repo' given, must be alphanumeric with optional underscores/dashes/dots in middle";
    return $1;
}

my $repos = "";
if($enablerepo){
    foreach(split(",", $enablerepo)){
        $opts .= " --enablerepo=" . validate_reponame($_);
    }
}
if($disablerepo){
    foreach(split(",", $disablerepo)){
        $opts .= " --disablerepo=" . validate_reponame($_);
    }
}

vlog2;
set_timeout();

$status = "UNKNOWN";

sub check_yum_returncode($$){
    my $returncode = shift;
    my @output     = shift;
    isInt($returncode) or code_error "non-int '$returncode' passed as first arg to check_yum_returncode()";
    if ($returncode == 0){
        # No Updates
        # pass
    } elsif ($returncode == 100){
        # Updates Available
        # pass
    } elsif ($returncode == 200){
        if ($output[-2] =~ /lock/ or $output[-2] =~ "another copy is running"){
            $msg = "Cannot check for updates, another instance of yum is running";
            warning unless($no_warn_on_lock);
            quit $status, $msg;
        } else {
            my @output2 = grep !/^Loading .+ plugin$/, @output;
            quit "UNKNOWN", "could't find loading plugin line in output: @output2";
        }
    } else {
        if(!grep /Loading "security" plugin/, @output or grep /Command line error: no such option: --security/, @output){
            quit "UNKNOWN", "Security plugin for yum is required. Try to 'yum install yum-security' (RHEL5) or 'yum install yum-plugin-security' (RHEL6) and then re-run this plugin. Alternatively, to just alert on any update which does not require the security plugin, try --all-updates";
        } else {
            quit "UNKNOWN", "@output";
        }
    }
}


sub check_all_updates(){
    my $number_updates = get_all_updates();
    if ($number_updates == 0){
        $status = "OK" if $status eq "UNKNOWN";
        $msg = "0 Updates Available | package_updates_available=0";
    } else {
        critical;
        plural $number_updates;
        $msg = "$number_updates Yum Update$plural Available | yum_updates_available=$number_updates";
    }
}


sub check_security_updates(){
    my ($number_security_updates, $number_other_updates) = get_security_updates();
    if($number_security_updates == 0){
        $status = "OK" if $status eq "UNKNOWN";
    } else {
        critical;
    }
    plural $number_security_updates;
    $msg = "$number_security_updates Yum Security Update$plural Available";
    if($number_other_updates != 0){
        warning if $warn_on_any_update;
    }
    plural $number_other_updates;
    $msg .= ", $number_other_updates Non-Security Update$plural Available | security_updates_available=$number_security_updates non_security_updates_available=$number_other_updates yum_updates_available=" . ($number_security_updates + $number_other_updates);
}


sub get_security_updates(){
    my ($result, @output) = cmd("$YUM $opts --security check-update", 0, 0, "get_returncode");
    check_yum_returncode($result, @output);
    my $summary_line_found = 0;
    my $number_security_updates;
    my $number_total_updates;
    foreach(@output){
        if(/No packages needed,? for security[;,] (\d+) (?:packages )?available/){
            $number_security_updates = 0;
            $number_total_updates    = $1;
            last;
        } elsif(/Needed (\d+) of (\d+) packages, for security/){
            $number_security_updates = $1;
            $number_total_updates    = $2;
            last;
        }
    }
    defined($number_security_updates) and defined($number_total_updates) or quit "UNKNOWN", "failed to determine the number of security & total updates. Format may have changed. $nagios_plugins_support_msg";
    my $number_other_updates = $number_total_updates - $number_security_updates;
    my @package_output = grep { $_ !~ / from .+ excluded / } @output;
    if(scalar(@package_output) > $number_total_updates + 25){
        quit "UNKNOWN", "Yum output signature is larger than current known format. Output format may have changed. $nagios_plugins_support_msg";
    }
    return ($number_security_updates, $number_other_updates);
}


sub get_all_updates(){
    my ($result, @output) = cmd("$YUM $opts check-update", 0, 0, "get_returncode");
    check_yum_returncode($result, @output);
    my @output2 = split("\n\n", join("\n", @output));
    my $number_packages;
    foreach(@output2){
        vlog3 "Section:\n$_\n";
    }
    if(scalar @output2 == 1){
        $number_packages = 0;
    } elsif(scalar @output2 == 2){
        if($output2[1] =~ /Setting up repositories/ or $output2[1] =~ /Loaded plugins: /){
            quit "UNKNOWN", "Yum output signature does not match current known format. Output format may have changed. $nagios_plugins_support_msg";
        }
        # avoid warning 'Use of implicit split to @_ is deprecated at check_yum.pl line 172.'
        my @packages = split("\n", $output2[1]);
        $number_packages = scalar @packages;
    } else {
        quit "UNKNOWN", "Yum output signature does not match current known format. Output format may have changed. $nagios_plugins_support_msg";
    }

    # Extra layer of checks. This is a security plugin so it's preferable to fail with an error rather than pass silently leaving you with an insecure system
    my $count = 0;
    foreach(@output){
        $count++ if /^.+\.(i[3456]86|x86_64|noarch)\s+.+\s+.+$/;
    }
    if($count != $number_packages){
        quit "UNKNOWN", "Error parsing package information, inconsistent package count (count=$count vs packages=$number_packages), yum output may have changed. $nagios_plugins_support_msg";
    }

    return $number_packages;
}


if($all_updates){
    check_all_updates();
} else {
    check_security_updates();
}

quit $status, $msg;
