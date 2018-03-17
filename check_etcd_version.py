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

Nagios Plugin to check the Etcd server version via its Rest API

Tested on Etcd 2.0, 2.1, 2.2, 2.3, 3.0

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
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import UnknownError, support_msg_api, version_regex
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckEtcdVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckEtcdVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Etcd'
        self.default_host = 'localhost'
        self.default_port = 2379
        self.path = '/version'
        # Etcd2.1+ response is json
        # Etcd2.0 response is non-json so parse and handle manually to cover both
        self.json = False
        self.auth = False
        self.cluster_version = None
        self.msg = 'Etcd msg not defined yet'
        self.ok()

    def parse(self, req):
        try:
            json_dict = json.loads(req.content)
        except ValueError:
            # probably Etcd2 - parse version manually
            _ = re.match('^etcd ({})$'.format(version_regex), req.content)
            if _:
                version = _.group(1)
                return version
            else:
                raise UnknownError('non-json response returned (not Etcd3?) ' + \
                                   'and could not parse Etcd2 version either. {}'.format(support_msg_api()))
        version = json_dict['etcdserver']
        self.cluster_version = json_dict['etcdcluster']
        return version

    def extra_info(self):
        if self.cluster_version is not None:
            return ', cluster version = {0}'.format(self.cluster_version)
        return ''


if __name__ == '__main__':
    CheckEtcdVersion().main()
