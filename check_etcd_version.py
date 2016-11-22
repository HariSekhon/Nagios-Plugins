#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-11-22 16:52:53 +0000 (Tue, 22 Nov 2016)
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

Nagios Plugin to check the deployed version of Etcd

Tested on Etcd 3.0.15

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import os
import re
import sys
import traceback
try:
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, support_msg_api
    from harisekhon.utils import validate_host, validate_port, validate_regex, isVersion
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckEtcdVersion(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckEtcdVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Etcd'
        self.default_host = 'localhost'
        self.default_port = 2379
        self.host = None
        self.port = None
        self.expected = None
        self.msg = '{0} version unknown - no message defined'.format(self.software)
        self.ok()

    def add_options(self):
        self.add_hostoption(name=self.software,
                            default_host=self.default_host,
                            default_port=self.default_port)
        self.add_opt('-e', '--expected', help='Expected version regex (optional)')

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        self.expected = self.get_opt('expected')
        if self.expected is not None:
            validate_regex(self.expected)
            log.info('expected version regex: %s', self.expected)

    def run(self):
        (version, cluster_version) = self.get_version()
        if not isVersion(version):
            qquit('UNKNOWN', '{0} version unrecognized \'{1}\'. {2}'\
                             .format(self.software, version, support_msg_api()))
        if not isVersion(cluster_version):
            qquit('UNKNOWN', '{0} cluster version unrecognized \'{1}\'. {2}'\
                             .format(self.software, cluster_version, support_msg_api()))
        self.msg = '{0} version = {1}'.format(self.software, version)
        if self.expected is not None and not re.search(self.expected, version):
            self.msg += " (expected '{0}')".format(self.expected)
            self.critical()
        #super(CheckEtcdVersion, self).run()
        self.msg += ', cluster version = {0}'.format(cluster_version)

    def get_version(self):
        log.info('querying %s', self.software)
        url = 'http://{host}:{port}/version'.format(host=self.host, port=self.port)
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        try:
            json_dict = json.loads(req.content)
            version = json_dict['etcdserver']
            cluster_version = json_dict['etcdcluster']
        except KeyError as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {error}. {support_msg}'\
                             .format(software=self.software, error=_, support_msg=support_msg_api()))
        return (version, cluster_version)


if __name__ == '__main__':
    CheckEtcdVersion().main()
