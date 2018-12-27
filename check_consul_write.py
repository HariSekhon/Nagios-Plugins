#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-16 00:46:07 +0000 (Sat, 16 Jan 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check Consul key-value store end-to-end via API write of a unique generated key => read back + validate
and finally delete cleanup of the generated key

Thresholds apply to max write / read / delete timings

Tested on Consul 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.nagiosplugin import KeyWriteNagiosPlugin
    from check_consul_key import CheckConsulKey
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.0'


class CheckConsulWrite(CheckConsulKey, KeyWriteNagiosPlugin):

    def write(self):
        url = 'http://%(host)s:%(port)s/v1/kv/%(key)s' % self.__dict__
        self.request_handler.check_response_code = \
            self.check_response_code("failed to write Consul key '{0}'".format(self.key))
        self.request_handler.put(url, self._write_value)

    def delete(self):
        url = 'http://%(host)s:%(port)s/v1/kv/%(key)s' % self.__dict__
        self.request_handler.check_response_code = \
            self.check_response_code("failed to delete Consul key '{0}'".format(self.key))
        self.request_handler.delete(url)


if __name__ == '__main__':
    CheckConsulWrite().main()
