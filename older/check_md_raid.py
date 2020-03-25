#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2007-02-21 16:15:32 +0000 (Wed, 21 Feb 2007)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

""" This plugin for Nagios uses the standard mdadm program to get the status
 of all the linux md arrays on the local machine using the mdadm utility"""

from __future__ import print_function

__author__ = "Hari Sekhon"
__title__ = "Nagios Plugin for Linux MD Software RAID"
__version__ = "0.7.4"

# pylint: disable=wrong-import-position
import os
import re
import sys
import argparse

# Standard Nagios return codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

# Full path to the mdadm utility check on the Raid state
BIN = "/sbin/mdadm"

def end(status, message):  # lgtm [py/similar-function]
    """exits the plugin with first arg as the return code and the second
    arg as the message to output"""

    if status == OK:
        print("RAID OK: %s" % message)
        sys.exit(OK)
    elif status == WARNING:
        print("RAID WARNING: %s" % message)
        sys.exit(WARNING)
    elif status == CRITICAL:
        print("RAID CRITICAL: %s" % message)
        sys.exit(CRITICAL)
    else:
        print("UNKNOWN: %s" % message)
        sys.exit(UNKNOWN)


if os.geteuid() != 0:
    end(UNKNOWN, "You must be root to run this plugin")

if not os.path.exists(BIN):
    end(UNKNOWN, "Raid utility '%s' cannot be found" % BIN)

if not os.access(BIN, os.X_OK):
    end(UNKNOWN, "Raid utility '%s' is not executable" % BIN)


def find_arrays(verbosity):
    """finds all MD arrays on local machine using mdadm and returns a list of
    them, or exits UNKNOWN if no MD arrays are found"""

    if verbosity >= 3:
        print("finding all MD arrays via: %s --detail --scan" % BIN)
    devices_output = os.popen("%s --detail --scan" % BIN).readlines()
    raid_devices = []
    for line in devices_output:
        if "ARRAY" in line:
            raid_device = line.split()[1]
            if verbosity >= 2:
                print("found array %s" % raid_device)
            raid_devices.append(raid_device)

    if not raid_devices:
        end(UNKNOWN, "no MD raid devices found on this machine")
    else:
        raid_devices.sort()
        return raid_devices


def test_raid(verbosity):
    """checks all MD arrays on local machine, returns status code"""

    raid_devices = find_arrays(verbosity)

    status = OK
    message = ""
    arrays_not_ok = 0
    number_arrays = len(raid_devices)
    for array in raid_devices:
        if verbosity >= 2:
            print('Now testing raid device "%s"' % array)

        detailed_output = os.popen("%s --detail %s" % (BIN, array)).readlines()

        if verbosity >= 3:
            for line in detailed_output:
                print(line,)

        state = "unknown"
        for line in detailed_output:
            if "State :" in line:
                state = line.split(":")[-1][1:-1]
                state = state.rstrip()
        re_clean = re.compile('^clean|active(,.*)?$')
        if not re_clean.match(state) and state != "active":
            arrays_not_ok += 1
            raidlevel = detailed_output[3].split()[-1]
            shortname = array.split("/")[-1].upper()
            if state == "dirty":
            # This happens when the array is under heavy usage but it's \
            # normal and the array recovers within seconds
                continue
            elif "recovering" in state:
                extra_info = None
                for line in detailed_output:
                    if "Rebuild Status" in line:
                        extra_info = line
                message += 'Array "%s" is in state ' % shortname
                if extra_info:
                    message += '"%s" (%s) - %s' \
                                    % (state, raidlevel, extra_info)
                else:
                    message += '"%s" (%s)' % (state, raidlevel)
                message += ", "
                if status == OK:
                    status = WARNING
            elif state == "unknown":
                message += 'State of Raid Array "%s" is unknown, ' % shortname
                if state == OK:
                    status = UNKNOWN
            else:
                message += 'Array %s is in state "%s" (%s), ' \
                                            % (shortname, state, raidlevel)
                status = CRITICAL

    message = message.rstrip(", ")

    if status == OK:
        message += "All arrays OK"
    else:
        if arrays_not_ok == 1:
            message = "1 array not ok - " + message
        else:
            message = "%s arrays not ok - " % arrays_not_ok + message

    if number_arrays == 1:
        message += " [1 array checked]"
    else:
        message += " [%s arrays checked]" % number_arrays

    return status, message

def parse_arguments():
    """parses args and calls func to test MD arrays"""

    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--verbose", action="count", dest="verbosity", default=0, help="Verbose mode. Good for testing plugin. By default\ only one result line is printed as per Nagios standards")
    parser.add_argument("-V", "--version", action="store_true", dest="version", help="Print version number and exit")

    args = parser.parse_args()

    return args.verbosity, args.version

def main():
    verbosity, version = parse_arguments()

    if version:
        print(__version__)
        sys.exit(OK)

    result, message = test_raid(verbosity)

    end(result, message)


if __name__ == "__main__":
    main()
