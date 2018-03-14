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

Nagios Plugin to check the health of a Hashicorp Vault instance via its API

Checks:

    - initialized
    - not standby (raises warning unless --standby is specified)
    - sealed / unsealed (optional, raises critical)
    - time skew between Vault server and local system vs warning / critical thresholds

Tested On Vault 0.6, 0.7, 0.8, 0.9

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import time
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
__version__ = '0.1'


class CheckVaultHealth(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckVaultHealth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Vault'
        self.default_port = 8200
        self.path = '/v1/sys/health'
        self.auth = False
        self.json = True
        self.msg = 'Vault msg not defined yet'

    def add_options(self):
        super(CheckVaultHealth, self).add_options()
        self.add_opt('--standby', action='store_true', help='Allow standby')
        self.add_opt('--sealed', action='store_true', help='Expect sealed')
        self.add_opt('--unsealed', action='store_true', help='Expect unsealed')
        self.add_thresholds(default_warning=60)

    def process_options(self):
        super(CheckVaultHealth, self).process_options()
        if self.get_opt('sealed') and self.get_opt('unsealed'):
            self.usage('--sealed and --unsealed are mutually exclusive')
        self.validate_thresholds(positive=True, integer=False, optional=True)

    def parse_json(self, json_data):
        initialized = json_data['initialized']
        cluster_name = json_data['cluster_name']
        #replication_dr_mode = json_data['replication_dr_mode']
        #replication_performance_mode = json_data['replication_performance_mode']
        sealed = json_data['sealed']
        server_time_utc = json_data['server_time_utc']
        standby = json_data['standby']
        self.msg = "Vault cluster '{}' ".format(cluster_name)
        if initialized:
            self.msg += 'initialized, '
        else:
            self.critical()
            self.msg += 'not initialized! '
        self.msg += 'standby = {}'.format(standby)
        if standby and not self.get_opt('standby'):
            self.warning()
            self.msg += '!'
        else:
            self.msg += ', '
        self.msg += 'sealed = {}'.format(sealed)
        if self.get_opt('sealed') and not sealed:
            self.critical()
            self.msg += ' (expected sealed)'
        elif self.get_opt('unsealed') and sealed:
            self.critical()
            self.msg += ' (expected unsealed)'
        time_diff = time.time() - server_time_utc
        self.msg += ', time skew = {:.2f} secs'.format(time_diff)
        self.check_thresholds(abs(time_diff))
        self.msg += ' | time_skew={}s{}'.format(time_diff, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckVaultHealth().main()
