Advanced HAProxy Configurations for Big Data, NoSQL and Web technologies
===============================

Advanced HAProxy configurations for Multi-Master, Active-Standby (Hadoop, HBase, Presto) and Peer-to-Peer technologies (Elasticsearch, SolrCloud etc).

They are designed both for production-grade High Availability to clients and also to make Monitoring and scripting easier.

These configurations contain specialised Health Checks for each system based on experience and code from the Advanced Nagios Plugins Collection and [PyTools](https://github.com/harisekhon/pytools) github repos.

They can be combined with VRRP-based High Availability solutions to create full production-grade High Availability solutions and come pre-tuned with advanced health checks and relevant settings, as well as some protections such as limiting access to these services to only private IP addressing schemes as they should rarely be accessed outside your private network.

You should use an expert consultant to tune to your needs but these should be extremely close to your finished production configurations.

All configurations should not be run together on the same HAProxy host as some of these technologies use the same port numbers by default, for example Ambari and Presto, so you would have to modify at least the frontend addresses if proxying both of those services on the same HAProxy host(s).

Configurations are split by service in the form of ```<service>.cfg``` and must be combined with ```10-global.cfg``` and ```20-defaults.cfg```:

```
haproxy -f 10-globals.cfg -f 20-defaults.cfg -f elasticsearch.cfg
```

Common backend server addresses has been pre-populated for convenience including the same name of the service which could be resolved to multiple IPs from DNS, ```192.168.99.100``` which is the common Docker Machine IP address, and ```docker``` - these sorts of addresses are used in continuous integration testing of this repo including these HAProxy configurations which are tested by running all the relevant nagios plugins for each service through HAProxy to validate the HAProxy configurations.

See also ```find_active_server.py``` from my [PyTools](https://github.com/harisekhon/pytools) repo and its related adjacent programs for on-the-fly command line determination of active masters or first responding peers across many of these same technologies etc.
