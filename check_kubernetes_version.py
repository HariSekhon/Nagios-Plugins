#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-05-04 18:34:40 +0100 (Fri, 04 May 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback # pylint: disable=line-too-long
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check the version of Kubernetes via its API

Verbose mode also outputs the build date

Tested on Kubernetes 1.13

"""

# Doesn't work on versions < 0.9, the API endpoint isn't found

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


# pylint: disable=too-few-public-methods
class CheckKubernetesVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckKubernetesVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Kubernetes API'
        self.path = '/version'
        self.default_port = 8001
        self.json = True
        self.auth = False
        self.msg = 'Kubernetes msg not defined'
        self.build_date = ''

#    def add_options(self):
#        super(CheckKubernetesVersion, self).add_options()
#        self.add_opt('-T', '--token', default=os.getenv('KUBERNETES_TOKEN', os.getenv('TOKEN')),
#                     help='Token to authenticate with ' + \
#                          '(optional, not needed if running through kubectl proxy ($K8S_TOKEN, $TOKEN)')

    def process_options(self):
        super(CheckKubernetesVersion, self).process_options()
        self.no_args()
#        token = self.get_opt('token')
#        if token:
#            self.headers['Authorization'] = 'Bearer {}'.format(token)

    # must be a method for inheritance to work
    def parse_json(self, json_data):  # pylint: disable=no-self-use
        self.build_date = json_data['buildDate']
        return json_data['gitVersion'].lstrip('v')

    def extra_info(self):
        if self.verbose:
            return ', build date = {}'.format(self.build_date)
        return ''


if __name__ == '__main__':
    CheckKubernetesVersion().main()
