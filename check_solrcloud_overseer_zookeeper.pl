#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-15 12:45:31 +0000 (Sun, 15 Feb 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the SolrCloud elected overseer in ZooKeeper

See also adjacent plugin check_solrcloud_overseer.pl which does the same as this check but via the Solr API on one of the SolrCloud servers instead of ZooKeeper, so doesn't require Net::ZooKeeper to be built.

Tested on ZooKeeper 3.4.5 / 3.4.6 with SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. API segfaults if you try to check the contents of a null znode such as those kept by SolrCloud servers eg. /solr/live_nodes/<hostname>:8983_solr - ie this will occur if you supply the incorrect base znode and it happens to be null
";

$VERSION = "0.2.1";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::ZooKeeper;

my $znode = "/overseer_elect/leader";
my $base  = "/solr";

%options = (
    %zookeeper_options,
    "b|base=s" => [ \$base, "Base Znode for Solr in ZooKeeper (default: /solr, should be just / for embedded or non-chrooted zookeeper)" ],
);
splice @usage_order, 6, 0, qw/base/;

get_options();

my @hosts = validate_hosts($host, $port);
$znode = validate_base_and_znode($base, $znode, "overseer leader");

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

vlog2;
set_timeout();

$status = "UNKNOWN";

connect_zookeepers(@hosts);

check_znode_exists($znode);

my $data = get_znode_contents_json($znode);

$status = "OK";

vlog2 "checking overseer elect leader znode";
my $overseer = get_field2($data, "id");
vlog2 "overseer = $overseer";
$overseer =~ s/^\d+-//;
$overseer =~ s/-n_\d+$//;
$overseer =~ s/_solr$//;

$msg = "SolrCloud overseer node = $overseer";

get_znode_age($znode);

$msg .= ", last state change " . sec2human($znode_age_secs)  . " ago | overseer_last_state_change=${znode_age_secs}s";

vlog2;
quit $status, $msg;
