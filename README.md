Advanced Nagios Plugins Collection
==================================

Largest and most advanced collection of unified Nagios monitoring code in the wild.

Largest collection of Hadoop & NoSQL monitoring code for Nagios, written by a former Clouderan (Cloudera is the original Hadoop Big Data company).

I've been developing this Nagios Plugin Collection since around 2006. The basic Nagios plugins collection that you get with Nagios is a great base to start from to cover some of the basics, while this extends Nagios monitoring capabilities significantly further especially in to the application layer, APIs etc.

This should be the next stop after installing Nagios with it's basic plugins, especially for those running web or NoSQL technologies (Hadoop, Cassandra, HBase, Redis, Riak etc).

These programs can also be run standalone on the command line or used in scripts as well as called in Nagios.

Enjoy

Hari Sekhon

Big Data Contractor

http://www.linkedin.com/in/harisekhon

### A Sample of cool Nagios Plugins in this collection ###

- ```check_ssl_cert.pl``` - SSL expiry, chain of trust (including intermediate certs important for certain mobile devices), domain, wildcard and multi-domain support validation
- ```check_mysql_query.pl``` - generic enough it obsoleted a dozen custom plugins and prevented writing many more
- ```check_mysql_config.pl``` - detect differences in your /etc/my.cnf and running MySQL config to catch DBAs making changes without saving to my.cnf or backporting to puppet, validate configuration compliance against a baseline
- ```check_hadoop_*``` - various Hadoop monitoring utilities covering health and metrics for HDFS & MapReduce
- ```check_hbase_*``` - various HBase monitoring utilities, covering Masters, RegionServers, table availability and metrics
- ```check_cloudera_manager_metrics.pl``` - fetch a wealth of Hadoop monitoring metrics from Cloudera Manager. Modern Hadoop users with Cloudera Manager will want to use this (Disclaimer: I worked for Cloudera, but seriously CM collects an impressive amount of metrics)
- ```check_puppet.rb``` - thorough, find out when Puppet stops properly applying manifests, if it's in the right environment, if it's --disabled, right puppet version etc
- ```check_riak_*``` - check Riak API writes/reads/deletes with timings, check specific key, check diagnostics, check nodes agree on ring status, gather statistics, alert on any single stat
- ```check_redis_*``` - check Redis API writes/reads/deletes with timings, check specific key, replication slaves, replicated writes, publish/subscribe, connected clients, validate configuration compliance, gather statistics, alert on any single stat
- ```check_memcached_*``` - check Memcached API writes/reads/deletes with timings, check specific key, current connections, gather statistics
- ```check_zookeeper.pl``` - ZooKeeper server checks, multiple layers: "is ok" status, is writable (quorum), operating mode (leader/follower vs standalone), gathers statistics
- ```check_zookeeper_znode.pl``` - ZooKeeper content checks, useful for HBase, SolrCloud, Hadoop NameNode HA & JobTracker HA (ZKFC) and any other ZooKeeper based service

... and there are many more. This code base is also under active development and there are many more cool plugins pending import.

### Quality ###

Most of the plugins I've read from Nagios Exchange and Monitoring Exchange in the last 8 years have not been of the quality required to run in production environments I've worked in (ever seen plugins written in Bash with little validation, or mere 200-300 line plugins without robust input/output validation and error handling, resulting in "UNKNOWN: (null)" when something goes wrong - right when you need them - then you know what I mean). That prompted me to write my own plugins whenever I had an idea or requirement.

That naturally evolved in to this, a relatively Advanced Collection of Nagios Plugins, especially when I began standardizing and reusing code between plugins and improving the quality of all those plugins while doing so.

##### Goals #####

- specific error messages to aid faster Root Cause Analysis
- consistent behaviour
- standardized switches
- strict input/output validation at all stages, written for security and robustness
- multiple verbosity levels
- self-timeouts
- graphing data where appropriate
- code reuse, especially for more complex input/output validations and error handling
- support for use of $USERNAME and $PASSWORD environment variables as well as more specific overrides (eg. $MYSQL_USERNAME, $REDIS_PASSWORD) to give administrators the option to avoid leaking --password credentials in the process list for all users to see
- easy rapid development of new high quality robust Nagios plugins with minimal lines of code

Several plugins have been merged together and replaced with symlinks to the unified plugins bookmarking their areas of functionality, similar to some plugins from the standard nagios plugins collection.

ePN support may be added in future but given that I've run 13,000 checks per Nagios server without ePN optimization it's not that high on the priority list right now.

##### Library #####

Having written a large number of Nagios Plugins in the last several years in a variety of languages (Python, Perl, Ruby, Bash, VBS) I abstracted out common components of a good robust Nagios Plugin program in to a library of reusable components that I leverage very heavily in all my modern plugins and other programs found under my other repos here on GitHub, which are now mostly written in Perl using this library, for reasons of both concise rapid development and speed of execution.

This Library enables writing much more thoroughly validated production quality code, to achieve in quick 200 lines of Perl what might otherwise take 1500-2000 lines (including some of the more complicated supporting code such as robust validation functions with long complex regexs, configurable self-timeouts, warning/critical threshold range logic, common options and generated usage, multiple levels of verbosity, debug mode etc), dramatically reducing the time to write high quality plugins down to mere hours and at the same time vastly improving the quality of the final code through code reuse, as well as benefitting from generic future improvements to the library.

This gives each plugin the appearance of being very short, because only the core logic of what you're trying to achieve is displayed in the plugin itself, the error handling is often handled in a library, so it may appear that a simple one line 'curl()' function call has no error handling at all around it but under the hood the error handling is handled inside the function inside a library, same for HBase Thrift API connection, Redis API connection etc so the client code as seen in the top level plugins knows it succeeded or otherwise the framework would have errored out with a specific error message such as "connection refused" etc...

I've tried to keep the quality here high so a lot of plugins I've written over the years haven't made it in to this collection, there are a lot still pending import, a couple others are in TODO-require-updates until I can reintegrate and test them with my current framework to modernize them, although they should still work with the tiny utils.pm from the standard nagios plugins collection.

I'm aware of Nagios::Plugin and will re-review whether to integrate it's usage into my library at some point.

###### Legacy ######

Some older plugins (especially those written in languages other than Perl) may not adhere to all of the criteria above so most have been filed away under the legacy/ directory (they were used by people out there in production so I didn't want to remove them entirely). Legacy plugins also indicate that I haven't run or made updates to them in a few years so those may require tweaks and updates.

If you're new remember to check out the legacy/ directory for more plugins that are less current but that you might find useful.

### Quick Setup ###

```
git clone https://github.com/harisekhon/nagios-plugins
cd nagios-plugins
make
```

This will use 'sudo' to install all required Perl modules from CPAN and then initialize my library git repo as a submodule. If you want to install some of the common Perl CPAN modules such as Net::DNS and LWP::* using your OS packages instead of installing from CPAN then follow the Manual Setup section below.

If wanting to use any of ZooKeeper znode checks for HBase/SolrCloud etc based on check_zookeeper_znode.pl you will also need to install the zookeeper libraries which has a separate build target due to having to install C bindings as well as the library itself on the local system. This will explicitly fetch the tested ZooKeeper 3.4.5, you'd have to update the Makefile if you want a different version.

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

###### Net::ZooKeeper for check_zookeeper_znode.pl (various znode checks for HBase/SolrCloud) ######

The ```check_zookeeper_znode.pl``` plugin requires the Net::ZooKeeper Perl CPAN module but this is not a simple ```cpan Net::ZooKeeper```, that will fail. Follow these instructions precisely or debug at your own peril:

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
which should return without errors or output if successful.

### Other Dependencies ###

Some plugins, especially ones under the legacy directory such as those that check 3ware/LSI raid controllers, SVN, VNC etc require external binaries to work, but the plugins will tell you if they are missing. Please see the respective vendor websites for 3ware, LSI etc to fetch those binaries and then re-run those plugins.

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

### Usage --help ###

All plugins come with --help which lists all options as well as giving a program description, often including a detailed account of what is checked in the code.

Just make sure to install the Perl CPAN modules listed above first as some plugins won't run until you've installed the required Perl modules.

### Further Utilities ###

Check out the https://github.com/harisekhon/sysadmin repository adjacent to this nagios-plugins repo for some other useful tools such as Hadoop HDFS per block read performance + location debugging tool (hadoop_hdfs_time_block_reads.jy), watch_url.pl for load balanced environments and other useful programs.
