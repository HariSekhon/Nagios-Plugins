#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-20 13:58:39 +0200 (Tue, 20 Jun 2017)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check HiveServer2 Interactive LLAP peers via the HTTP Rest API

Optional checks:

- number of peers online vs warning/critical thresholds
- specific peer available (regex against node FQDN)

Tested on Hive 1.2.1 on Hortonworks HDP 2.6.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon.utils import isList, validate_regex, plural
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5'


class CheckHiveServer2InteractivePeers(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHiveServer2InteractivePeers, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'HiveServer2 Interactive LLAP'
        self.msg = self.name + ': '
        self.default_port = 15002
        self.path = 'peers'
        self.json = True
        self.auth = False
        self.regex = None

    def add_options(self):
        super(CheckHiveServer2InteractivePeers, self).add_options()
        self.add_opt('-r', '--regex', metavar='host', help='Regex of host fqdn to expect in peer list (optional)')
        self.add_thresholds()

    def process_options(self):
        super(CheckHiveServer2InteractivePeers, self).process_options()
        self.regex = self.get_opt('regex')
        if self.regex is not None:
            validate_regex(self.regex, 'peer')
        self.validate_thresholds(simple='lower', optional=True)

    def get_key(self, json_data, key):
        try:
            return json_data[key]
        except KeyError:
            raise UnknownError('\'{0}\' key was not returned in output from '.format(key) +
                               'HiveServer2 Interactive instance at {0}:{1}. {2}'\
                               .format(self.host, self.port, support_msg_api()))

    def find_peer(self, regex, peers):
        for peer in peers:
            host = self.get_key(peer, 'host')
            if regex.match(host):
                return host
        return False

    def parse_json(self, json_data):
        dynamic = self.get_key(json_data, 'dynamic')
        peers = self.get_key(json_data, 'peers')
        if not isList(peers):
            raise UnknownError('\'peers\' field is not a list as expected! {0}'.format(support_msg_api()))
        peer_count = len(peers)
        if self.regex:
            regex = re.compile(self.regex, re.I)
            if not self.find_peer(regex, peers):
                self.msg += 'no peer found matching \'{0}\', '.format(self.regex)
                self.critical()
        self.msg += '{0} peer{1} found'.format(peer_count, plural(peer_count))
        self.check_thresholds(peer_count)
        self.msg += ', dynamic = {0}'.format(dynamic)
        self.msg += ' | hiveserver2_llap_peers={0}{1}'.format(peer_count, self.get_perf_thresholds(boundary='lower'))


if __name__ == '__main__':
    CheckHiveServer2InteractivePeers().main()
