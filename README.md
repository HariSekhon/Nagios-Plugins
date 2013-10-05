Advanced Nagios Plugins Collection
==================================

I've been developing this Nagios Plugin Collection since around 2006. The basic Nagios plugins collection that you get with Nagios is a great base to start from to cover some of the basics, while this extends Nagios monitoring capabilities significantly further especially in to the application layer, APIs etc.

I highly recommended that all Nagios users consider becoming familiar with this suite of tools.

These programs can also be run standalone on the command line or used in scripts as well as called in Nagios.

Enjoy

Hari Sekhon

http://www.linkedin.com/in/harisekhon

### A Sample of cool Nagios Plugins in this collection ###

- check_ssl_cert.pl     - SSL expiry, chain of trust (including intermediate certs important for certain mobile devices), domain, wildcard and multi-domain support validation
- check_mysql_query.pl  - generic enough it obsoleted a dozen custom plugins and prevented writing many more
- check_mysql_config.pl - detect differences in your /etc/my.cnf and running MySQL config to catch DBAs making changes without saving to my.cnf or backporting to puppet
- check_hadoop_cloudera_manager_metrics.pl - fetch a wealth of Hadoop monitoring metrics from Cloudera Manager. Modern Hadoop users with Cloudera Manager will want to use this (Disclaimer: I work for Cloudera, but seriously CM collects an impressive amount of metrics)
- check_puppet.rb                   - thorough, find out when Puppet stops properly applying manifests, if it's in the right environment, if it's puppetd --disabled, right puppet version etc
- check_hadoop_* / check_hbase_*    - various hadoop monitoring utilities covering lots of different aspects of HDFS, MapReduce and HBase functionality and metrics
- check_memcached_*                 - check Memcached API writes/reads with timings, gather statistics
- check_riak_*                      - check Riak API writes/reads/deletes with timings, check nodes agree on ring status, gather statistics
- check_zookeeper.pl                - multiple layers of checks of ZooKeeper, is ok and writable (quorum), operating mode (leader/follower vs standalone), gather statistics

... and there are many more ...

### Quality ###

Most of the plugins I've read from Nagios Exchange and Monitoring Exchange in the last 8 years have not been of the quality required to run in production environments I've worked in (ever seen plugins written in Bash with little validation, or mere 200-300 line plugins without robust input and error handling, resulting in "UNKNOWN: (null)" right when you need them - then you know what I mean). That prompted me to write my own plugins whenever I had an idea, requirement or request, with an emphasis on input validation, error handling and reporting as specific information as possible in an error situation. This naturally evolved in to this plugins collection over the years, especially when I began standardizing and reusing code between plugins.

Library - Having written a large number of Nagios Plugins in the last several years in a variety of languages (Python, Perl, Ruby, Bash, VBS) I abstracted out common components of a good robust Nagios Plugin program in to a library of reusable components that I leverage very heavily in all my modern plugins, which are now mostly written in Perl for both concise rapid development and speed of execution.

This Library enables writing much more thoroughly validated production quality code, to achieve in 200 lines of Perl what might otherwise take 1500-2000 lines (including some of the more complicated supporting code such as robust validation functions with long complex regexs, configurable self-timeouts, warning/critical threshold range logic, common options and generated usage, multiple levels of verbosity, debug mode etc), dramatically reducing the time to write good quality plugins down to mere hours and at the same time vastly improving the quality of the final code, as well as benefitting from generic future improvements. This gives each plugin the appearance of being very short, because only the core logic of what you're trying to achieve is displayed in the plugin itself.

I've tried to keep the quality here high so a lot of plugins I've written over the years haven't made it in to this collection, and a couple others are in TODO-require-updates until I can reintegrate and test them with my current framework, although they should still work with the tiny utils.pm from the standard plugins collection. Several other older plugins are under the "legacy" directory indicating I haven't run or made updates to them in a few years so they may require tweaks and updates.

Remember to check out the legacy/ directory for more plugins that are less current but that you might find useful.

### Setup ###

Fetch my library repo which is included as a submodule (it's shared between these Nagios Plugins and other programs I've written over the years)

```
cd nagios-plugins
```
```
git submodule init
```
```
git submodule update
```

Then install the CPAN modules for whichever plugins you want to use, which are listed in the Makefile

### One-shot Makefile setup ###

```
make
```

Running make as root will install all required CPAN modules by calling cpan <list of modules> and then doing the git submodule init and git submodule update to pull in my library git repo. You may not want to do this if you're not owning the repo as root and also because you may want to install some of the stock Perl modules such as Net::DNS and LWP::* using your OS packages instead of CPAN.

### Other Dependencies ###

Most plugins run with minimal dependencies for operational ease of use. Some plugins require CPAN modules as mentioned above, and some of those under the legacy directory such as those that check 3ware/LSI raid controllers, SVN, VNC etc require external binaries to work, but the plugins will tell you if they are missing. Please see the respective vendor websites for 3ware, LSI etc to fetch those binaries and then re-run the plugins where needed.

See 'Makefile' for the list of Perl modules that you need to install

### Usage ###

All plugins come with --help which lists all options as well as giving a program description, often including a detailed account of what is checked in the code.
