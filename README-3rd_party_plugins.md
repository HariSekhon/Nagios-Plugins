3rd Party Nagios Plugins
========================

This is a list of the best and most interesting 3rd party plugins, several of which I have used or come across over the years that deserve mention, usually due to their better quality than the typical Nagios Exchange / Icinga Exchange plugins.

- [check_openmanage](http://folk.uio.no/trondham/software/check_openmanage.html) - Dell OpenManage hardware monitoring plugin by Trond Hasle Amundsen - checks RAID, Processors, Memory, Fans, Temperature, Power Supplies etc. Top quality widely used plugin - one of my all time favourites
- [Consol Labs](https://labs.consol.de/) checks - one of the very best quality publishers of Nagios Plugins (I have a lot of respect for this team):
  - [check_hpasm](https://labs.consol.de/nagios/check_hpasm/index.html) - HP ASM hardware monitoring plugin - checks RAID, Processors, Memory, Fans, Temperature, Power supplies
  - [check_logfiles](https://labs.consol.de/nagios/check_logfiles/index.html) - the best log monitoring Nagios Plugin I've seen, even accounts for log rotations
  - [check_webinject](https://labs.consol.de/nagios/check_webinject/index.html) - see below
- [WebInject](http://www.webinject.org/plugin.html) - authenticate through HTTP Login portals and check the inside. Widely used and flexible via external XML config. Excellent  - I used to use this a lot and it's probably the best of it's kind
- [Jolokia](https://jolokia.org/) - JMX-HTTP bridge to make monitoring JMX easier via Rest calls from non-JVM scripting languages. This is far more scalable than running lots of JVM Nagios Plugins which have higher startup overhead
  - [check_jmx4perl](https://exchange.nagios.org/directory/Plugins/Java-Applications-and-Servers/check_jmx4perl/details) - use with Jolokia
- [Percona plugins](https://www.percona.com/doc/percona-monitoring-plugins/latest/index.html) - MySQL plugins from MySQL specialists
- [check_drbd](https://exchange.nagios.org/directory/Plugins/Operating-Systems/Linux/check_drbd/details) - can't remember if this is the plugin I used to use but I used to love it telling me when DRBD was behind by how much and caught up
- [check_tsd](https://github.com/OpenTSDB/opentsdb/blob/master/tools/check_tsd) - OpenTSDB metrics query
- [check_prometheus_metric.sh](https://github.com/prometheus/nagios_plugins/blob/master/check_prometheus_metric.sh) - I don't normally rate bash scripts as Nagios Plugins but this is in the official project so it's worth a look
- [collectd-nagios](https://collectd.org/documentation/manpages/collectd-nagios.1.shtml) - queries Collectd metrics for Nagios alerting
- [collectd exec-nagios.px](https://github.com/collectd/collectd/blob/master/contrib/exec-nagios.px) - executes a Nagios Plugin and returns the metrics to Collectd to forward on to one of the many compatible metrics graphing solutions
