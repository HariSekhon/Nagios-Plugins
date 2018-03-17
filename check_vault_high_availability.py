#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-14 18:04:54 +0000 (Wed, 14 Mar 2018)
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

Nagios Plugin to check HashiCorp Vault high availability via its API

Checks:

    - is High Availability enabled
    - is current instance the leader (optionally raises warning if --leader specified and is not the leader)
    - verbose mode outputs the leader address
    - raises warning if no leader found (checks leader address is populated)

Tested On Vault 0.6, 0.7, 0.8, 0.9

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckVaultHighAvailability(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckVaultHighAvailability, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Vault'
        self.default_port = 8200
        self.path = '/v1/sys/leader'
        self.auth = False
        self.json = True
        self.msg = 'Vault msg not defined yet'

    def add_options(self):
        super(CheckVaultHighAvailability, self).add_options()
        self.add_opt('--leader', action='store_true', help='Expect to be leader')

    #def process_options(self):
    #    super(CheckVaultHighAvailability, self).process_options()

    def parse_json(self, json_data):
        ha_enabled = json_data['ha_enabled']
        is_leader = json_data['is_self']
        leader_address = json_data['leader_address']
        leader_cluster_address = None
        # not available on older versions
        if 'leader_cluster_address' in json_data:
            leader_cluster_address = json_data['leader_cluster_address']
        self.msg = 'Vault high availability enabled = {}'.format(ha_enabled)
        if ha_enabled:
            self.msg += ', '
        else:
            self.critical()
            self.msg += '! '
        self.msg += 'is leader = {}'.format(is_leader)
        if not is_leader and self.get_opt('leader'):
            self.warning()
            self.msg += ' (expected to be leader)'
        if self.verbose:
            self.msg += ", leader_address = '{}'".format(leader_address)
            # not available on older versions
            if leader_cluster_address is not None:
                self.msg += ", leader_cluster_address = '{}'".format(leader_cluster_address)
        if not leader_address or (leader_cluster_address is not None and not leader_cluster_address):
            self.critical()
            self.msg += ', no leader found!'


if __name__ == '__main__':
    CheckVaultHighAvailability().main()
