Advanced Nagios Plugins Collection
==================================

I've been developing this Nagios Plugin Collection since around 2006. The basic Nagios plugins collection that you get with Nagios is a great base to start from to cover some of the basics, while this extends Nagios monitoring capabilities significantly further especially in to the application layer, APIs etc.

I highly recommended that all Nagios users consider becoming familiar with this suite of tools.

These programs can also be run standalone on the command line or used in scripts as well as called in Nagios.

Enjoy

Hari Sekhon

http://www.linkedin.com/in/harisekhon

### A Sample of cool Nagios Plugins in this collection ###

- ```check_ssl_cert.pl``` - SSL expiry, chain of trust (including intermediate certs important for certain mobile devices), domain, wildcard and multi-domain support validation
- ```check_mysql_query.pl``` - generic enough it obsoleted a dozen custom plugins and prevented writing many more
- ```check_mysql_config.pl``` - detect differences in your /etc/my.cnf and running MySQL config to catch DBAs making changes without saving to my.cnf or backporting to puppet
- ```check_hadoop_*``` - various Hadoop monitoring utilities covering health and metrics for HDFS & MapReduce
- ```check_hbase_*``` - various HBase monitoring utilities, covering Masters, RegionServers, table availability and metrics
- ```check_cloudera_manager_metrics.pl``` - fetch a wealth of Hadoop monitoring metrics from Cloudera Manager. Modern Hadoop users with Cloudera Manager will want to use this (Disclaimer: I work for Cloudera, but seriously CM collects an impressive amount of metrics)
- ```check_puppet.rb``` - thorough, find out when Puppet stops properly applying manifests, if it's in the right environment, if it's --disabled, right puppet version etc
- ```check_memcached_*``` - check Memcached API writes/reads with timings, gathers statistics
- ```check_riak_*``` - check Riak API writes/reads/deletes with timings, checks diagnostics, checks nodes agree on ring status, gathers statistics
- ```check_zookeeper.pl``` - ZooKeeper server checks, multiple layers: "is ok" status, is writable (quorum), operating mode (leader/follower vs standalone), gathers statistics
- ```check_zookeeper_znode.pl``` - ZooKeeper content checks, useful for HBase, SolrCloud, Hadoop NameNode HA & JobTracker HA (ZKFC) and any other ZooKeeper based service

... and there are many more ...

### Quality ###

Most of the plugins I've read from Nagios Exchange and Monitoring Exchange in the last 8 years have not been of the quality required to run in production environments I've worked in (ever seen plugins written in Bash with little validation, or mere 200-300 line plugins without robust input/output validation and error handling, resulting in "UNKNOWN: (null)" when something goes wrong - right when you need them - then you know what I mean). That prompted me to write my own plugins whenever I had an idea or requirement.

That naturally evolved in to this, a relatively Advanced Collection of Nagios Plugins, especially when I began standardizing and reusing code between plugins and improving the quality of all those plugins while doing so.

##### Goals #####

- specific error messages to aid faster Root Cause Analysis
- consistent behaviour
- standardized switches
- strict input/output validation at all stages
- multiple verbosity levels
- self-timeouts
- graphing data where appropriate
- code reuse, especially for more complex validations
- easy rapid development of new high quality Nagios plugins

Some older plugins (especially those written in languages other than Perl) may not adhere to all of these criteria so most have been filed away under the legacy/ directory (they were used in production so I didn't want to remove them entirely).

##### Library #####

Having written a large number of Nagios Plugins in the last several years in a variety of languages (Python, Perl, Ruby, Bash, VBS) I abstracted out common components of a good robust Nagios Plugin program in to a library of reusable components that I leverage very heavily in all my modern plugins and other programs found under my other repos here on GitHub, which are now mostly written in Perl using this library, for reasons of both concise rapid development and speed of execution.

This Library enables writing much more thoroughly validated production quality code, to achieve in quick 200 lines of Perl what might otherwise take 1500-2000 lines (including some of the more complicated supporting code such as robust validation functions with long complex regexs, configurable self-timeouts, warning/critical threshold range logic, common options and generated usage, multiple levels of verbosity, debug mode etc), dramatically reducing the time to write high quality plugins down to mere hours and at the same time vastly improving the quality of the final code through code reuse, as well as benefitting from generic future improvements to the library.

This gives each plugin the appearance of being very short, because only the core logic of what you're trying to achieve is displayed in the plugin itself.

I've tried to keep the quality here high so a lot of plugins I've written over the years haven't made it in to this collection, and a couple others are in TODO-require-updates until I can reintegrate and test them with my current framework, although they should still work with the tiny utils.pm from the standard nagios plugins collection.

Several other older plugins are under the "legacy" directory indicating I haven't run or made updates to them in a few years so they may require tweaks and updates but were useful in production at one point so I didn't want to remove them entirely as I know people out there are using them.

If you're new remember to check out the legacy/ directory for more plugins that are less current but that you might find useful.

### Quick Setup ###

```
git clone https://github.com/harisekhon/nagios-plugins
cd nagios-plugins
make
```

This will use 'sudo' to install all required Perl modules from CPAN and then initialize my library git repo as a submodule. If you want to install some of the common Perl CPAN modules such as Net::DNS and LWP::* using your OS packages instead of installing from CPAN then follow the Manual Setup section below.

### Manual Setup ###

Fetch my library repo which is included as a submodule (it's shared between these Nagios Plugins and other programs I've written over the years).

```
git clone https://github.com/harisekhon/nagios-plugins
cd nagios-plugins
git submodule init
git submodule update
```

Then install the Perl CPAN modules for whichever plugins you want to use, which are all listed in the Makefile. I suggest just installing them all for quick simplicity using one of the two methods listed next.

##### Perl CPAN Modules #####

If installing the Perl CPAN modules via your package manager or by hand instead of running the 'make' command as listed above, then read the 'Makefile' file for the list of Perl CPAN modules that you need to install.

### Other Dependencies ###

Most plugins run with minimal dependencies for operational ease of use. Some plugins require Perl CPAN modules as mentioned above, and some of those under the legacy directory such as those that check 3ware/LSI raid controllers, SVN, VNC etc require external binaries to work, but the plugins will tell you if they are missing. Please see the respective vendor websites for 3ware, LSI etc to fetch those binaries and then re-run the plugins where needed.

The ```check_puppet.rb``` plugin uses Puppet's native Ruby libraries to parse the Puppet config and as such will only be run where Puppet is properly installed.

The ```check_logserver.py``` "Syslog to MySQL" plugin will need the Python MySQL module to be installed which you should be able to find via your package manager. If using RHEL/CentOS do:

```
yum install MySQL-python
```

The ```check_zookeeper_znode.pl``` plugin requires the Net::ZooKeeper Perl CPAN module but this is not a simple ```cpan Net::ZooKeeper```, that will fail. Follow these instructions precisely or debug at your own peril:

Run these commands as root.
```
# install C client library
export ZOOKEEPER_VERSION=3.4.5
wget http://www.mirrorservice.org/sites/ftp.apache.org/zookeeper/zookeeper-$ZOOKEEPER_VERSION/zookeeper-$ZOOKEEPER_VERSION.tar.gz
tar zxvf zookeeper-$ZOOKEEPER_VERSION.tar.gz
cd zookeeper-$ZOOKEEPER_VERSION/src/c
./configure
make install

# now install Perl module using C library with the correct linking
cd ../contrib/zkperl
perl Makefile.PL --zookeeper-include=/usr/local/include/zookeeper --zookeeper-lib=/usr/local/lib
LD_RUN_PATH=/usr/local/lib make install
```
After this check it's properly installed by doing
```perl -e "use Net::ZooKeeper"```
which should return without errors or output if successful.

### Usage --help ###

All plugins come with --help which lists all options as well as giving a program description, often including a detailed account of what is checked in the code.

Just make sure to install the Perl CPAN modules listed above first as some plugins won't run until you've installed the required Perl modules.
