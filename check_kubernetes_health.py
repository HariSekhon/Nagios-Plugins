#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-02-26 18:30:53 +0000 (Tue, 26 Feb 2019)
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

Nagios Plugin to check the health status of Kubernetes via its API

Tested on Kubernetes 1.13

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
__version__ = '0.2.1'


class CheckKubernetesHealth(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckKubernetesHealth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Kubernetes API'
        self.default_port = 8001
        # or just /healthz
        self.path = '/healthz/ping'
        self.auth = 'optional'
        self.json = False
        self.msg = 'Kubernetes msg not defined yet'

    def add_options(self):
        super(CheckKubernetesHealth, self).add_options()
        self.add_opt('-T', '--token', default=os.getenv('KUBERNETES_TOKEN', os.getenv('TOKEN')),
                     help='Token to authenticate with ' + \
                          '(optional, not needed if running through kubectl proxy ($KUBERNETES_TOKEN, $TOKEN)')

    def process_options(self):
        super(CheckKubernetesHealth, self).process_options()
        self.no_args()
        token = self.get_opt('token')
        if token:
            self.headers['Authorization'] = 'Bearer {}'.format(token)

    def parse(self, req):
        content = req.content
        if content != 'ok':
            self.critical()
        self.msg = "Kubernetes health = '{}'".format(content)


if __name__ == '__main__':
    CheckKubernetesHealth().main()
