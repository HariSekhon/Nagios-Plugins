#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-23 17:49:21 +0100 (Mon, 23 May 2016)
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

Nagios Plugin to check the deployed version of Solr matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of Solr
for compatibility for all my other Solr / SolrCloud nagios plugins.

Tested on Solr 4.10, 5.5, 6.0, 6.1, 6.2, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import logging
import os
import sys
import traceback
try:
    from bs4 import BeautifulSoup
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, support_msg_api, isJson
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'

# pylint: disable=too-few-public-methods


class CheckSolrVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckSolrVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Solr'
        self.path = '/solr/admin/info/system'
        self.default_port = 8983
        self.json = False
        self.auth = 'optional'
        self.msg = 'Solr version message not defined yet'

    # must be a method for inheritance to work
    # pylint: disable=no-self-use
    def parse(self, req):
        # versions 7.0+
        if isJson(req.content):
            json_data = json.loads(req.content)
            version = json_data['lucene']['solr-spec-version']
        else:
            soup = BeautifulSoup(req.content, 'html.parser')
            if log.isEnabledFor(logging.DEBUG):
                log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
            try:
                version = soup.find('str', {'name':'solr-spec-version'}).text
            except (AttributeError, TypeError):
                qquit('UNKNOWN', 'failed to find parse Solr output. {0}\n{1}'\
                                 .format(support_msg_api(), traceback.format_exc()))
        return version


if __name__ == '__main__':
    CheckSolrVersion().main()
