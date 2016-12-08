#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-07 11:04:16 +0000 (Wed, 07 Dec 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check Attivio AIE metrics via the Performance Monitor host's REST API

Can list all metric names for convenience

Optional thresholds may be supplied, which will apply to any retrieved metrics. Verbose mode will output the thresholds
in the perfdata (can become too long for Nagios to handle so off by default).

As there are quite a lot of metric subcomponents, allows several filters to be applied and
also makes each metric name specifically distinguishable via a explicit naming scheme:

<metric>.<nodeset>.<hostname>.<workflowType>.<workflow>.<component>.<path>.<networkInterface>=<value>

Each component of the naming scheme is only output if there is a corresponding distinguishing attribute
returned by the API. To more clearly see the sub-components that you can filter on, run in -vv mode

Tested on Attivio 5.1.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import json
import os
import sys
import traceback
try:
    import requests
    #from requests.auth import HTTPBasicAuth
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, qquit, ERRORS, support_msg_api, isDict, isList, isFloat, jsonpp
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5'


class CheckAttivioMetrics(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAttivioMetrics, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Attivio AIE'
        self.default_host = 'localhost'
        self.default_port = 16960
        self.host = self.default_host
        self.port = self.default_port
        self.protocol = 'http'
        self.msg = '{0} metrics:'.format(self.software)
        self.metrics = None
        self.filter_types = ('nodeset', 'hostname', 'workflow', 'component', 'path', 'networkInterface')
        self.filters = {}
        self.precision = None
        self.ok()

    def add_options(self):
        self.add_hostoption(name=self.software, default_host=self.default_host, default_port=self.default_port)
        # no authentication is required to access Attivio's AIE system status page
        #self.add_useroption(name=self.software, default_user=self.default_user)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_opt('-m', '--metrics', help='Metrics to retrieve, comma separated')
        self.add_opt('-N', '--nodeset', help='Nodeset to restrict metrics to')
        self.add_opt('-O', '--hostname', help='Hostname to restrict metrics to')
        self.add_opt('-W', '--workflow', help='Workflow name to restrict metrics to')
        self.add_opt('-C', '--component', help='Component name to restrict metrics to')
        self.add_opt('-A', '--path', help='OS Path to restrict metrics to (eg. /boot, / etc)')
        self.add_opt('-I', '--networkInterface', help='Network interface to restrict metrics to (eg. eno... - <ip>)')
        self.add_opt('-p', '--precision', default=4,
                     help='Decimal place precision for floating point numbers (default: 4)')
        self.add_opt('-l', '--list-metrics', action='store_true', help='List all metrics and exit')
        self.add_thresholds()

    def process_options(self):
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        ssl = self.get_opt('ssl')
        log_option('ssl', ssl)
        if ssl:
            self.protocol = 'https'
        self.metrics = self.get_opt('metrics')
        if not self.metrics and not self.get_opt('list_metrics'):
            self.usage("--metrics not specified, use --list-metrics to see what's available in Attivio's API")
        for key in self.filter_types:
            self.filters[key] = self.get_opt(key)
        self.precision = self.get_opt('precision')
        self.validate_thresholds(optional=True)

    def run(self):
        try:
            if self.get_opt('list_metrics'):
                self.list_metrics()
            json_struct = self.get('lastdata', params={'metrics': self.metrics})
            metrics = self.parse_metrics(json_struct)
            self.msg_metrics(metrics)
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))

    def parse_metrics(self, json_struct):
        if not isList(json_struct):
            raise ValueError("non-list returned by Attivio AIE Perfmon metrics API (got type '{0}')"\
                             .format(type(json_struct)))
        metrics = {}
        if not json_struct:
            qquit('UNKNOWN', "no matching metrics found for '{0}'".format(self.metrics) + \
                             ", use --list-metrics to check you've specified a correct metric")
        for item in json_struct:
            if not isDict(item):
                raise ValueError("non-dict item found in list returned by Attivio AIE Perfmon API (got type '{0}')"\
                                 .format(type(item)))
            if not isList(item['values']):
                raise ValueError("non-list returned for metric value by Attivio AIE Perfmon API (got type '{0}')"\
                                 .format(type(item['values'])))
            metric = item['metric']
            log.info('metric = %s', metric)
            if self.skip_metric(item):
                log.info('skipping metric %s due to filters', metric)
                continue
            for key in ('nodeset', 'hostname', 'workflowType', 'workflow', 'component', 'path', 'networkInterface'):
                if key in item:
                    val = item[key]
                    log.info('%s = %s', key, val)
                    # Attivio returns network interfaces in form "lo - 127.0.0.1"
                    if key == 'networkInterface':
                        val = val.split()[0]
                    metric += '.{0}'.format(val)
            value = item['values'][0]
            log.info('value = %s\n', value)
            if self.precision and isFloat(value):
                # leaving as string will result in lots of trailing zeros
                value = float('{value:.{precision}f}'.format(value=value, precision=self.precision))
            if metric in metrics:
                qquit('UNKNOWN', "duplicate metric '{metric}' discovered! {support_msg}"\
                                 .format(metric=metric, support_msg=support_msg_api()))
            metrics[metric] = value
        return metrics

    def skip_metric(self, item):
        for key in self.filter_types:
            if self.filters[key] and key in item:
                # Attivio returns network interfaces in form "lo - 127.0.0.1"
                if key == 'networkInterface':
                    if self.filters[key] != item[key].split()[0]:
                        return True
                else:
                    if self.filters[key] != item[key]:
                        return True
        return False

    def msg_metrics(self, metrics):
        if not metrics:
            qquit('UNKNOWN', "no matching metrics found, check your filters: --" + " / --".join(self.filter_types))
        for metric in sorted(metrics):
            value = metrics[metric]
            self.msg += ' {metric}={value}'.format(metric=metric, value=value)
        #if len(metrics) == 1:
            #self.check_thresholds(metrics.itervalues().next())
            # safer for python 3 without having to use six.next(six.itervalues(metrics))
            #metric = metrics.keys()[0]
            #value = metrics[metric]
            if isFloat(value):
                self.check_thresholds(value)
        self.msg += ' |'
        for metric in sorted(metrics):
            value = metrics[metric]
            # try not to break graphing when Attivio gives us 'NaN' value
            if not isFloat(value):
                value = 0
            self.msg += " '{metric}'={value}".format(metric=metric, value=value)
            if self.verbose:
                self.msg += self.get_perf_thresholds()

    def get(self, url_suffix, params=None):
        log.info('querying %s', self.software)
        url = '{protocol}://{host}:{port}/rest/metrics/{url_suffix}'\
              .format(host=self.host, port=self.port, protocol=self.protocol, url_suffix=url_suffix)
        log.debug('GET %s', url)
        try:
            req = requests.get(url, params=params)
            #req = requests.get(url, auth=HTTPBasicAuth(self.user, self.password))
        except requests.exceptions.RequestException as _:
            errhint = ''
            if 'BadStatusLine' in str(_.message):
                errhint = ' (possibly connecting to an SSL secured port without using --ssl?)'
            elif self.protocol == 'https' and 'unknown protocol' in str(_.message):
                errhint = ' (possibly connecting to a plain HTTP port with the -S / --ssl switch enabled?)'
            qquit('CRITICAL', str(_) + errhint)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', '{0}: {1}'.format(req.status_code, req.reason))
        json_struct = json.loads(req.content)
        if log.isEnabledFor(logging.DEBUG):
            print(jsonpp(req.content))
            print('='*80)
        return json_struct

    def list_metrics(self):
        json_struct = self.get('names')
        if not isList(json_struct):
            raise ValueError("non-list returned by Attivio Perfmon host for metric names (got type '{0}'"\
                             .format(type(json_struct)))
        print('Attivio metrics:\n')
        for metric in sorted(json_struct):
            print(metric)
        sys.exit(ERRORS['UNKNOWN'])


if __name__ == '__main__':
    CheckAttivioMetrics().main()
