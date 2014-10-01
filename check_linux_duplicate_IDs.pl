#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-10-01 22:59:18 +0100 (Wed, 01 Oct 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check Linux for duplicate UID/GUIDs and duplicate user/group names

This is surprisingly common with centralized account systems such as LDAP integrated Linux servers. Locally added user/group accounts increment the highest local UID/GUID number (happens every time you install new packages which run under their own accounts) but centralized account systems like LDAP also naiively increment their own highest UID/GUID numbers without checking if those IDs are used on any of the depending servers as just happened when adding those recent packages. I've seen this several times over the last several years and it usually goes unnoticed. I've written scripts to detect this several years ago but just realized I never released a standard check for this. This is something all Linux sysadmins should deploy, especially those working with centralized account systems such as LDAP as this subtle flaw in your deployment configuration/management can breach security controls such as ACLs.

See also pwck and grpck if there are duplicates in your /etc/passwd or /etc/group files. Old school obvious but having another account with UID/GUID 0 means you've probably been rooted.

Checks:

- duplicate user  IDs (UIDs),  outputs UIDs  and the user  names overlapping on those UIDs
- duplicate group IDs (GUIDs), outputs GUIDs and the group names overlapping on those GUIDs
- duplicate user  names, outputs the user  names with their UIDs
- duplicate group names, outputs the group names with their GUIDs";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $getent = "/usr/bin/getent";

get_options();

linux_only();

vlog2;
set_timeout();

$status = "OK";

my @output;
vlog2 "fetching user information";
@output = cmd("$getent passwd");
my $user;
my $uid;
my %users;
my %uids;
my %user_counts;
my %uid_counts;
my %duplicate_users;
my %duplicate_uids;
foreach(@output){
    /^([^:]*+):[^:]*:([^:]*):/ or quit "UNKNOWN", "unrecognized line output from getent passwd: '$_'. $nagios_plugins_support_msg";
    $user = $1;
    $uid  = $2;
    defined($user) or quit "CRITICAL", "user name not defined in output line: '$_'";
    defined($uid)  or quit "CRITICAL", "UID not defined in output line: '$_'";
    $user_counts{$user}++;
    $uid_counts{$uid}++;
    $users{$user}{$uid} = 1;
    $users{$user}{$uid} = 1;
    $uids{$uid}{$user}  = 1;
    $uids{$uid}{$user}  = 1;
    if($user_counts{$user} > 1){
        $duplicate_users{$user}++;
    }
    if($uid_counts{$uid} > 1){
        $duplicate_uids{$uid}++;
    }
}

my %duplicate_user_uids;
my %duplicate_uid_users;
foreach(sort keys %duplicate_users){
    @{$duplicate_user_uids{$_}} = sort keys %{$users{$_}};
}
foreach(sort keys %duplicate_uids){
    @{$duplicate_uid_users{$_}} = sort keys %{$uids{$_}};
}

vlog2 "fetching group information";
@output = cmd("$getent group");
my $group;
my $guid;
my %groups;
my %guids;
my %group_counts;
my %guid_counts;
my %duplicate_groups;
my %duplicate_guids;
foreach(@output){
    /^([^:]*+):[^:]*:([^:]*):/ or quit "UNKNOWN", "unrecognized line output from getent group: '$_'. $nagios_plugins_support_msg";
    $group = $1;
    $guid  = $2;
    defined($group) or quit "CRITICAL", "group name not defined in output line: '$_'";
    defined($guid)  or quit "CRITICAL", "GUID not defined in output line: '$_'";
    $group_counts{$group}++;
    $guid_counts{$guid}++;
    $groups{$group}{$guid} = 1;
    $groups{$group}{$guid} = 1;
    $guids{$guid}{$group}  = 1;
    $guids{$guid}{$group}  = 1;
    if($group_counts{$group} > 1){
        $duplicate_groups{$group}++;
    }
    if($guid_counts{$guid} > 1){
        $duplicate_guids{$guid}++;
    }
}

my %duplicate_group_guids;
my %duplicate_guid_groups;
foreach(sort keys %duplicate_groups){
    @{$duplicate_group_guids{$_}} = sort keys %{$groups{$_}};
}
foreach(sort keys %duplicate_guids){
    @{$duplicate_guid_groups{$_}} = sort keys %{$guids{$_}};
}

sub check_duplicates($$$){
    my $ref   = shift;
    my $name  = shift;
    my $name2 = shift;
    vlog2 "checking for duplicate ${name}s";
    if(%{$ref}){
        $msg .= "duplicate ${name}s detected: ";
        foreach(sort keys %{$ref}){
             $msg .= "$_\[${name2}s:" . join(",", @{${$ref}{$_}}) . "] ";
        }
        $msg =~ s/\s*$//;
        $msg .= ", ";
    }
}

if(%duplicate_user_uids or %duplicate_uid_users){
    critical;
    check_duplicates(\%duplicate_user_uids,   "user",  "UID"  );
    check_duplicates(\%duplicate_uid_users,   "UID",   "user" );
    check_duplicates(\%duplicate_group_guids, "group", "guid" );
    check_duplicates(\%duplicate_guid_groups, "GUID",  "group");
    $msg =~ s/, $//;
} else {
    $msg .= "no duplicate UIDs / GUIDs or user / group names";
}

vlog2;
quit $status, $msg;
