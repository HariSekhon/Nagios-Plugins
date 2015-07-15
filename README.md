Advanced Nagios Plugins Collection [![Build Status](https://travis-ci.org/harisekhon/nagios-plugins.svg?branch=master)](https://travis-ci.org/harisekhon/nagios-plugins)
==================================

Largest and most advanced collection of unified production-grade Nagios monitoring code in the wild.

Largest collection of Hadoop & NoSQL monitoring code, written by a former Clouderan (Cloudera was the first Hadoop Big Data vendor).

Hadoop and extensive API integration with all major Hadoop vendors (Hortonworks, Cloudera, MapR, IBM).

I've been developing this Nagios Plugin Collection since 2006. The basic Nagios plugins collection that you get with Nagios is a great base to start from to cover some of the basics, while this extends Nagios monitoring capabilities significantly further especially in to the application layer, APIs etc.

It's a treasure trove of essentials for every single "DevOp", sysadmin or engineer, with extensive goodies for those running Web, Hadoop and NoSQL technologies (Cassandra, HBase, MongoDB, Riak, Couchbase, Memcached, Redis, Solr, SolrCloud, ElasticSearch etc).

These programs can also be run standalone on the command line as tools and used in scripts as well as run via Nagios.

This should be the next stop after installing Nagios with it's basic plugins.

I also take suggestions for interesting new plugins or those involving interesting open source technologies.

Github pull requests for patches and features are more than welcome.

Hari Sekhon

Big Data Contractor, United Kingdom

http://www.linkedin.com/in/harisekhon


##### Make sure you run ```make update``` if updating and not just ```git pull``` as you will often need the latest library submodule and possibly new upstream libraries. #####


### A Sample of cool Nagios Plugins in this collection ###

- ```check_ssl_cert.pl``` - SSL expiry, chain of trust (including intermediate certs important for certain mobile devices), SNI, domain, wildcard and multi-domain support validation
- ```check_whois.pl``` - check domain expiry days left and registration details match expected
- ```check_mysql_query.pl``` - generic enough it obsoleted a dozen custom MySQL plugins and prevented writing many more
- ```check_mysql_config.pl``` - detect differences in your /etc/my.cnf and running MySQL config to catch DBAs making changes to running databases without saving to /etc/my.cnf or backporting to Puppet. Can also be used to remotely validate configuration compliance against a known good baseline
- ```check_hadoop_*.pl``` - various Apache Hadoop monitoring utilities for HDFS, YARN and MapReduce (both MRv1 & MRv2) including HDFS cluster balance, block replication, space, block count limits per datanode / cluster total, node counts, dead Datanodes/TaskTrackers/NodeManagers, blacklisted TaskTrackers, unhealthy NodeManagers, Namenode & JobTracker / Yarn Resource Manager heap usage, NameNode & JobTracker HA, NameNode safe mode, WebHDFS (with HDFS HA failover support), HttpFS, HDFS writeability, HDFS fsck, HDFS file / directory existence & metadata attributes, gather metrics
- ```check_kafka.pl``` - checks Kafka brokers end-to-end via API, acts as both a producer and a consumer and checks that a unique generated message passes through the Kafka broker cluster successfully
- ```check_hbase_*.pl``` - various HBase monitoring utilities using Thrift + Stargate APIs, checking Masters/Backup Masters, RegionServers, table availability, unassigned regions, gather metrics
- ```check_cassandra_*.pl / check_datastax_opscenter_*.pl``` - Cassandra and DataStax OpsCenter monitoring, including Cassandra cluster nodes, token balance, space, heap, keyspace replication settings, alerts, backups, best practice rule checks, DSE hadoop analytics service status and both nodetool and DataStax OpsCenter collected metrics
- ```check_solr*.pl``` - checks for Solr and SolrCloud including API write/read/delete, arbitrary Solr queries vs num matching documents, API ping, Solr Core Heap / Index Size / Number of Docs for a given Solr Collection, and thresholds in ms against all Solr API operations as well as perfdata for graphing, as well as SolrCloud ZooKeeper content checks for collection shards and replicas states, number of live nodes in SolrCloud cluster, overseer, SolrCloud config and Solr metrics.
- ```check_elasticsearch_*.pl``` - checks Elasticsearch cluster state, shards, replicas, number of nodes & data nodes online, shard and disk % balance between nodes, single node ok, specific node found in cluster, per index: existence, shards, replicas, settings, age, stats at cluster / index / node levels, elasticsearch / lucene versions
- ```check_ambari_*.pl``` - Hadoop cluster checks via Hortonworks Ambari API - checks the status of services, nodes and config managed by Ambari
- ```check_cloudera_manager_*.pl``` - Hadoop cluster checks via Cloudera Manager API - checks states and health of cluster services/roles/nodes, management services, config staleness, Cloudera Enterprise license expiry, Cloudera Manager and CDH cluster versions, utility switches to list clusters/services/roles/nodes as well as list users and their role privileges, fetch a wealth of Hadoop & OS monitoring metrics from Cloudera Manager and compare to thresholds. Disclaimer: I worked for Cloudera, but seriously CM collects an impressive amount of metrics making check_cloudera_manager_metrics.pl alone a very versatile program from which to create hundreds of checks to flexibly alert on
- ```check_mapr*.pl``` - Hadoop cluster checks via MapR Control System API - checks services and nodes, MapR-FS space (cluster and per volume), volume states, volume block replication, volume snapshots and mirroring, MapR-FS per disk space utilization on nodes, failed disks, CLDB heartbeats, MapR alarms, MapReduce mode and memory utilization, disk and role balancer metrics. These are noticeably faster than running equivalent maprcli commands (exceptions: disk/role balancer use maprcli).
- ```check_ibm_biginsights_*.pl``` - Hadoop cluster checks via IBM BigInsights Console API - checks services, nodes, agents, BigSheets workbook runs, dfs paths and properties, HDFS space and block replication, BI console version, BI console applications deployed
- ```check_apache_drill_metrics.pl``` - check metrics from an Apache Drill node, apply thresholds to a given metric or return multiple or all metrics
- ```check_riak_*.pl``` - check Riak API writes/reads/deletes with timings, check a specific key's value against regex or value range, check all riak diagnostics, check node states, check all nodes agree on ring status, gather statistics, alert on any single stat
- ```check_redis_*.pl``` - check Redis API writes/reads/deletes with timings, check specific key's value against regex or value range, replication slaves I/O, replicated writes (write on master -> read from slave), publish/subscribe, connected clients, validate redis.conf against running server to check deployments or remote compliance checks, gather statistics, alert on any single stat
- ```check_memcached_*.pl``` - check Memcached API writes/reads/deletes with timings, check specific key's value against regex or value range, number of current connections, gather statistics
- ```check_zookeeper.pl``` - ZooKeeper server checks, multiple layers: "is ok" status, is writable (quorum), operating mode (leader/follower vs standalone), gather statistics
- ```check_zookeeper_*znode*.pl``` - ZooKeeper znode checks using ZK Perl API, useful for HBase, Kafka, SolrCloud, Hadoop NameNode HA & JobTracker HA (ZKFC) and any other ZooKeeper based service. Very versatile with multiple optional checks including data vs regex, json field extraction, ephemeral status, child znodes, znode last modified age
- ```check_puppet.rb``` - thorough, find out when Puppet stops properly applying manifests, if it's in the right environment, if it's --disabled, right puppet version etc

... and there are many more.

This code base is under active development and there are many more cool plugins pending import.

### Quality ###

Most of the plugins I've read from Nagios Exchange and Monitoring Exchange (now Icinga Exchange) in the last decade have not been of the quality required to run in production environments I've worked in (ever seen plugins written in Bash with little validation, or mere 200-300 line plugins without robust input/output validation and error handling, resulting in "UNKNOWN: (null)" when something goes wrong - right when you need them - then you know what I mean). That prompted me to write my own plugins whenever I had an idea or requirement.

That naturally evolved in to this, a relatively Advanced Collection of Nagios Plugins, especially when I began standardizing and reusing code between plugins and improving the quality of all those plugins while doing so.

##### Goals #####

- specific error messages to aid faster Root Cause Analysis
- consistent behaviour
- standardized switches
- strict input/output validation at all stages, written for security and robustness
- multiple verbosity levels
- self-timeouts
- graphing data where appropriate (use PNP4Nagios for automatic graphing)
- code reuse, especially for more complex input/output validations and error handling
- support for use of $USERNAME and $PASSWORD environment variables as well as more specific overrides (eg. $MYSQL_USERNAME, $REDIS_PASSWORD) to give administrators the option to avoid leaking --password credentials in the process list for all users to see
- continuous integration with unit tests for the custom supporting libraries and functional tests for the plugins of NoSQL technologies and datastores natively supported by Travis CI (currently Cassandra, Elasticsearch, Memcached, MongoDB, MySQL, Neo4j, Redis, Riak)
- easy rapid development of new high quality robust Nagios plugins with minimal lines of code

Several plugins have been merged together and replaced with symlinks to the unified plugins bookmarking their areas of functionality, similar to some plugins from the standard nagios plugins collection.

Some plugins such as those relating to Redis and Couchbase also have different modes and expose different options when called as different program names, so those symlinks are not just cosmetic. An example of this is write replication, which exposes extra options to read from a slave after writing to the master to check that replication is 100% working.

ePN optimization is not supported at this time by any of the plugins as I ran 13,000 checks per Nagios server years ago without ePN optimization - it's not worth the effort.

##### Contributions #####

Patches, improvements and even general feedback are welcome in the form of GitHub pull requests and issue tickets.

Examples of your usage and outputs are also welcome for the Wiki as some of these plugins allow a great diversity of checks to be created - for example, free form MySQL queries or ZooKeeper contents checks can be used to check pretty much anything that advanced DBAs and applications/operations personnel can think of with a just a few command line --switches.

##### Library #####

Having written a large number of Nagios Plugins in the last several years in a variety of languages (Python, Perl, Ruby, Bash, VBS) I abstracted out common components of a good robust Nagios Plugin program in to a library of reusable components that I leverage very heavily in all my modern plugins and other programs found under my other repos here on GitHub, which are now mostly written in Perl using this library, for reasons of both concise rapid development and speed of execution.

This Library enables writing much more thoroughly validated production quality code, to achieve in a quick 200 lines of Perl what might otherwise take 1500-2000 lines (including some of the more complicated supporting code such as robust validation functions with long complex regexs, configurable self-timeouts, warning/critical threshold range logic, common options and generated usage, multiple levels of verbosity, debug mode etc), dramatically reducing the time to write high quality plugins down to mere hours and at the same time vastly improving the quality of the final code through code reuse, as well as benefitting from generic future improvements to the library.

This gives each plugin the appearance of being very short, because only the core logic of what you're trying to achieve is displayed in the plugin itself, mostly composition of utility functions, and the error handling is often handled in a library too, so it may appear that a simple one line 'curl()' utility function call has no error handling at all around it but under the hood the error handling is handled inside the function inside a library, same for HBase Thrift API connection, Redis API connection etc so the client code as seen in the top level plugins knows it succeeded or otherwise the framework would have errored out with a specific error message such as "connection refused" etc... there is a lot of buried error checking code and a lot of utility functions so many operations become one-liners at the top level instead of huge programs that are hard to read and maintain.

I've tried to keep the quality here high so a lot of plugins I've written over the years haven't made it in to this collection, there are a lot still pending import, a couple others ```check_nsca.pl``` and ```check_syslog-ng_stats.pl``` are in the more/ directory until I get round to reintegrating and testing them with my current framework to modernize them, although they should still work with the tiny utils.pm from the standard nagios plugins collection.

I'm aware of Nagios::Plugin but my library has a lot more utility functions in it and I've written it to be highly convenient for me to develop with.

###### Older Plugins ######

Some older plugins (especially those written in languages other than Perl) may not adhere to all of the criteria above so most have been filed away under the older/ directory (they were used by people out there in production so I didn't want to remove them entirely). Older plugins also indicate that I haven't run or made updates to them in a few years so those may require tweaks and updates.

If you're new remember to check out the older/ directory for more plugins that are less current but that you might find useful.

### Quick Setup ###

Building is basically one ```make``` command.

Don't copy plugins out as most require the co-located libraries I've written so you should copy this directory as a whole after building it - it's simpler than trying to extract bits and pieces.

Be aware this will install yum rpms / apt debs automatically as well as a load of CPAN modules for Perl. If you don't want all that stuff automatically installed you must use the manual setup further down. You may need to install the GNU make system package if the make command isn't found (```yum install make```)

```
git clone https://github.com/harisekhon/nagios-plugins
cd nagios-plugins
make
```

This will use 'sudo' to install all required Perl modules from CPAN and then initialize my library git repo as a submodule. If you want to install some of the common Perl CPAN modules such as Net::DNS and LWP::* using your OS packages instead of installing from CPAN then follow the Manual Setup section below.

If wanting to use any of ZooKeeper znode checks for HBase/SolrCloud etc based on check_zookeeper_znode.pl or any of the check_solrcloud_*_zookeeper.pl programs you will also need to install the zookeeper libraries which has a separate build target due to having to install C bindings as well as the library itself on the local system. This will explicitly fetch the tested ZooKeeper 3.4.5, you'd have to update the ```ZOOKEEPER_VERSION``` variable in the Makefile if you want a different version.

```
make zookeeper
```
This downloads, builds and installs the ZooKeeper C bindings which Net::ZooKeeper needs. To clean up the working directory afterwards run:
```
make clean
```

### Manual Setup ###

Fetch my library repo which is included as a submodule (it's shared between these Nagios Plugins and other programs I've written over the years).

```
git clone https://github.com/harisekhon/nagios-plugins
cd nagios-plugins
git submodule init
git submodule update
```

Then install the Perl CPAN and Python modules as listed in the next sections.

##### Perl CPAN Modules #####

If installing the Perl CPAN modules via your package manager or by hand instead of running the 'make' command as listed in Quick Setup, then read the 'Makefile' file for the list of Perl CPAN modules that you need to install.

###### Net::ZooKeeper (for various ZooKeeper content checks for Kafka, HBase, SolrCloud etc) ######

```
check_zookeeper_znode.pl
check_zookeeper_child_znodes.pl
check_hbase_*_znode.pl
check_solrcloud_*_zookeeper.pl
```

The above listed programs require the Net::ZooKeeper Perl CPAN module but this is not a simple ```cpan Net::ZooKeeper```, that will fail. Follow these instructions precisely or debug at your own peril:

```
# install C client library
export ZOOKEEPER_VERSION=3.4.5
[ -f zookeeper-$ZOOKEEPER_VERSION.tar.gz ] || wget -O zookeeper-$ZOOKEEPER_VERSION.tar.gz http://www.mirrorservice.org/sites/ftp.apache.org/zookeeper/zookeeper-$ZOOKEEPER_VERSION/zookeeper-$ZOOKEEPER_VERSION.tar.gz
tar zxvf zookeeper-$ZOOKEEPER_VERSION.tar.gz
cd zookeeper-$ZOOKEEPER_VERSION/src/c
./configure
make
sudo make install

# now install Perl module using C library with the correct linking
cd ../contrib/zkperl
perl Makefile.PL --zookeeper-include=/usr/local/include/zookeeper --zookeeper-lib=/usr/local/lib
LD_RUN_PATH=/usr/local/lib make
sudo make install
```
After this check it's properly installed by doing
```perl -e "use Net::ZooKeeper"```
which should return no errors if successful.

###### MongoDB / Readonly library bug ######

The MongoDB Perl driver from CPAN doesn't seem to compile properly on RHEL5 based systems. PyMongo rewrite was considered but the extensive library of functions results in better code quality for the Perl plugins, it's easier to just upgrade your OS to RHEL6.

The MongoDB Perl driver does compile on RHEL6 but there is a small bug in the Readonly CPAN module that the MongoDB CPAN module uses. When it tries to call Readonly::XS, a MAGIC_COOKIE mismatch results in the following error:
```
Readonly::XS is not a standalone module. You should not use it directly. at /usr/local/lib64/perl5/Readonly/XS.pm line 34.
```
The workaround is to edit the Readonly module and comment out the ```eval 'use Readonly::XS'``` on line 33 of the Readonly module.

This is located here on Linux:
```
/usr/local/share/perl5/Readonly.pm
```

and here on Max OS X:
```
/Library/Perl/5.16/Readonly.pm
```

### Other Dependencies ###

Some plugins, especially ones under the older/ directory such as those that check 3ware/LSI raid controllers, SVN, VNC etc require external binaries to work, but the plugins will tell you if they are missing. Please see the respective vendor websites for 3ware, LSI etc to fetch those binaries and then re-run those plugins.

The ```check_puppet.rb``` plugin uses Puppet's native Ruby libraries to parse the Puppet config and as such will only be run where Puppet is properly installed.

The ```check_logserver.py``` "Syslog to MySQL" plugin will need the Python MySQL module to be installed which you should be able to find via your package manager. If using RHEL/CentOS do:

```
sudo yum install MySQL-python
```

or try install via pip, but this requires MySQL to be installed locally in order to build the Python egg...
```
sudo easy_install pip
sudo pip install MySQL-python
```

### Updating ###

Run ```make update```. This will git pull and then git submodule update which is necessary to pick up corresponding library updates, then try to build again using 'make install' to fetch any new CPAN dependencies.

If you update often and want to just quickly git pull + submodule update but skip rebuilding all those dependencies each time then run ```make update2``` (will miss new library dependencies - do full ```make update``` if you encounter issues).

### Usage --help ###

All plugins come with --help which lists all options as well as giving a program description, often including a detailed account of what is checked in the code.

Just make sure to install the Perl CPAN modules listed above first as some plugins won't run until you've installed the required Perl modules.

### Support for Bugs or Feature Requests ###

Please raise a ticket on Github for any bugs or problems encountered in the use of this code (Issues near the top right).

Please make sure you have run ```make``` first to pull the latest library submodule and build the necessary CPAN modules, (see [Quick Setup](https://github.com/harisekhon/nagios-plugins#quick-setup) above).

Make sure you run the code by hand on the command line with the ```-vvv``` switch for additional debug output and paste the full output in to the issue ticket. If you want to anonymize your hostnames/IP addresses etc you may use the ```scrub.pl``` found in my [Toolbox](https://github.com/harisekhon/toolbox) repo.

### Contributions ###

Contributions are more than welcome with patches accepted in the form of Github pull requests, for which you will receive attribution automatically as Github tracks these merges.

### Further Utilities ###

[ToolBox repo](https://github.com/harisekhon/toolbox) - contains 30+ programs including useful tools such as:
* Hive / Pig => Elasticsearch / SolrCloud indexers
* Hadoop HDFS performance debugger, native checksum extractor, file retention policy script, HDFS file stats, XML & running Hadoop cluster config differ
* ```watch_url.pl``` for debugging load balanced web farms
* tools for Ambari, Pig, Hive, Spark + IPython Notebook, Solr CLI
* code reCaser for SQL / Pig / Neo4j / Hive HQL / Cassandra / MySQL / PostgreSQL / Impala / MSSQL / Oracle
* ```scrub.pl``` anonymizes configs / logs for posting online - replaces hostnames/domains/FQDNs, IPs, passwords/keys in Cisco/Juniper configs, custom extensible phrases like your name or your company name

### See Also ###

* [My Perl/Python library](https://github.com/harisekhon/lib) - used throughout this code as a submodule to make the programs in this repo short
* [Spark => Elasticsearch](https://github.com/harisekhon/spark-to-elasticsearch) - Scala application to index from Spark to Elasticsearch. Used to index data in Hadoop clusters or local data via Spark standalone. This started as a Scala Spark port of my ```pig-text-to-elasticsearch.pig``` from [Toolbox](https://github.com/harisekhon/toolbox)

##### Weblinks #####

* Official Nagios Homepage: http://www.nagios.org/
* Nagios Command Configuration: http://nagios.sourceforge.net/docs/3_0/objectdefinitions.html#command
* Nagios Service Configuration: http://nagios.sourceforge.net/docs/3_0/objectdefinitions.html#service

* Icinga (newer alternative to Nagios): https://www.icinga.org/

###### Datameer ######

Datameer plugins referenced from Datameer docs in the Weblinks section along with the official Nagios links. See here for more information on Datameer monitoring with Nagios:

* http://www.datameer.com/documentation/display/DAS30/Monitoring+Hadoop+and+Datameer+using+Nagios

After trying the 1 example plugin there, return to try the 9 plugins in this collection to extend your Datameer monitoring further.
