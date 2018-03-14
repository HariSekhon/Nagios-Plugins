Advanced HAProxy Configurations for Big Data, NoSQL and Web technologies
===============================

Advanced HAProxy configurations for Multi-Master, Active-Standby (Hadoop, HBase, Presto) and Peer-to-Peer technologies (Elasticsearch, SolrCloud etc).

They are designed both for production-grade High Availability and also to make scripting and monitoring easier when connecting to APIs.

These configurations contain specialised Health Checks for each system based on experience and code from the [Advanced Nagios Plugins Collection](https://github.com/harisekhon/nagios-plugins#advanced-nagios-plugins-collection) and [PyTools](https://github.com/harisekhon/pytools) github repos.

They can be combined with VRRP-based High Availability solutions to create full production-grade High Availability load balancer solutions and come pre-tuned with advanced health checks and relevant settings, as well as some protections such as limiting access to these services to only private IP addressing schemes as they should rarely be accessed outside your private network.

You should use an expert consultant to tune to your needs but these should be extremely close to your finished production configurations.

All configurations should not be run together on the same HAProxy host as some of these technologies use the same port numbers by default, for example Ambari and Presto both default to port 8080, so you would have to modify at least the frontend HAProxy bind addresses if proxying both of those services on the same HAProxy host(s).

Configurations are split by service in the form of ```<service>.cfg``` for mix-and-match convenience and must be combined with ```10-global.cfg``` and ```20-defaults.cfg``` settings like so:

```
haproxy -f 10-globals.cfg -f 20-defaults.cfg -f elasticsearch.cfg
```

If you want to add a stats / admin UI then include the ```30-stats.cfg``` configuration:
```
haproxy -f 10-globals.cfg -f 20-defaults.cfg -f 30-stats.cfg -f elasticsearch.cfg
```

For multiple services just add those service configurations to the command line options:
```
haproxy -f 10-globals.cfg -f 20-defaults.cfg -f 30-stats.cfg -f elasticsearch.cfg -f solrcloud.cfg
```

Common backend server addresses have been pre-populated for convenience including:

- ```<service>``` - generic service name matching the proxied technology - could be resolved by DNS to multiple IPs to be balanced across
- ```192.168.99.100``` - the common Docker Machine IP address
- ```docker``` - again DNS resolve to your Docker location

These addresses are used in continuous integration testing of this repo including these HAProxy configurations which are tested by running all the relevant nagios plugins for each service through HAProxy to validate the HAProxy configurations.

See the ```untested/``` directory for a few more including SSL config versions I haven't got round to testing yet but should work.

See also ```find_active_server.py``` from my [PyTools](https://github.com/harisekhon/pytools) repo and its related adjacent programs for on-the-fly command line determination of active masters or first responding peers across many of these same technologies.
