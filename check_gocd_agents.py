#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-03-27 22:34:24 +0000 (Fri, 27 Mar 2020)
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

Nagios Plugin to check the number of healthy GoCD agents via the GoCD server API

Tested on GoCD 20.2.0

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
__version__ = '0.2.0'


class CheckGoCDServerHealth(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGoCDServerHealth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'GoCD'
        self.default_port = 8153
        self.path = '/go/api/agents'
        self.headers = {
            'Accept': 'application/vnd.go.cd.v6+json'
        }
        self.auth = 'optional'
        self.json = True
        self.msg = 'GoCD msg not defined yet'

    def add_options(self):
        super(CheckGoCDServerHealth, self).add_options()
        self.add_thresholds(default_warning=1, default_critical=1)

    def process_options(self):
        super(CheckGoCDServerHealth, self).process_options()
        self.validate_thresholds(simple='lower')

    def parse_json(self, json_data):
        agents = json_data['_embedded']['agents']
        num_agents = len(agents)
        num_agents_enabled = len([_ for _ in agents if _['agent_config_state'] == 'Enabled'])
        agent_states = {
            'Idle': 0,
            'Building': 0,
            'LostContact': 0,
            'Missing': 0,
            'Unknown': 0
        }
        num_agents_working = 0
        for agent in agents:
            agent_state = agent['agent_state']
            agent_states[agent_state] += 1
            if agent_state in ('LostContact', 'Missing', 'Unknown'):
                continue
            if agent['agent_config_state'] != 'Enabled':
                continue
            num_agents_working += 1
        self.msg = 'GoCD agents = {}/{}'.format(num_agents_working, num_agents)
        self.check_thresholds(num_agents_working)
        self.msg += ', enabled = {}'.format(num_agents_enabled)
        perfdata = ' | num_agents={}'.format(num_agents)
        perfdata += ' num_agents_enabled={}'.format(num_agents_enabled)
        perfdata += ' num_agents_working={}'.format(num_agents_working)
        perfdata += '{}'.format(self.get_perf_thresholds(boundary='lower'))
        for state in sorted(agent_states):
            self.msg += ', {} = {}'.format(state, agent_states[state])
            perfdata += ' {}={}'.format(state, agent_states[state])
        self.msg += perfdata


if __name__ == '__main__':
    CheckGoCDServerHealth().main()
