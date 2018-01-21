3rd Party Nagios Plugins
========================

This is a list of the best and most interesting 3rd party plugins, several of which I have used to come across over the years that deserve mention, usually due to their better quality than the typical Nagios Exchange / Icinga Exchange plugins.

- [check_openmanage](http://folk.uio.no/trondham/software/check_openmanage.html) - Dell OpenManage Hardware monitoring plugin by Trond Hasle Amundsen
- [check_drbd](https://exchange.nagios.org/directory/Plugins/Operating-Systems/Linux/check_drbd/details) - can't remember if this is the plugin I used to use but I used to love it telling me when DRBD was behind by how much and caught up
- [check_tsd](https://github.com/OpenTSDB/opentsdb/blob/master/tools/check_tsd) - OpenTSDB metrics query
- [check_prometheus_metric.sh](https://github.com/prometheus/nagios_plugins/blob/master/check_prometheus_metric.sh) - I don't normally bash scripts as Nagios Plugins but this is in the official project so is worth a look
- [collectd-nagios](https://collectd.org/documentation/manpages/collectd-nagios.1.shtml) - queries Collectd metrics for Nagios alerting
- [collectd exec-nagios.px](https://github.com/collectd/collectd/blob/master/contrib/exec-nagios.px) - executes a Nagios Plugin and returns the metric to Collectd to forward on to one of the many compatible metrics graphite solutions
