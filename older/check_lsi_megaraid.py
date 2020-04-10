#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2007-02-22 17:27:33 +0000 (Thu, 22 Feb 2007)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""Nagios plugin to test the status of all arrays on all LSI MegaRAID
controllers on the local machine. Uses the megarc.bin program written by LSI to
get the status of all arrays on all local LSI MegaRAID controllers. Expects the
megarc.bin program to be in the same directory as this plugin"""

from __future__ import print_function

# pylint: disable=wrong-import-position
import os
import sys
from optparse import OptionParser
# pylint: disable=ungrouped-imports
try:
    # Python 2
    from commands import getstatusoutput  # pylint: disable=no-name-in-module
except ImportError:
    # Python 3
    from subprocess import getstatusoutput  # pylint: disable=no-name-in-module

__author__ = "Hari Sekhon"
__title__ = "Nagios Plugin for LSI MegaRAID"
__version__ = "0.9.0"

# Standard Nagios return codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

SRCDIR = os.path.dirname(sys.argv[0])
BIN = SRCDIR + "/megarc.bin"
MEGADEV = "/dev/megadev0"


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


def make_megadev(devicenode):
    """Creates the device node needed for the Lsi utility to work
    (usually /dev/megadev0)"""

    try:
        devices = open("/proc/devices", "r")
        lines = devices.read()
        devices.close()
    except IOError as error:
        end(UNKNOWN, "Error reading /proc/devices while trying to create " \
                   + "device node '%s' - %s" % (devicenode, error))
    device = ""
    for line in lines.split("\n"):
        line = line.split()
        if len(line) > 1:
            major_number = line[0]
            device = line[1]
            if device == "megadev":
                break

    if device != "megadev":
        end(UNKNOWN, "Unable to create device node /dev/megadev0. Megadev " \
                   + "not found in /proc/devices. Please make sure you have " \
                   + "an Lsi MegaRaid card detected by your kernel first")
    cmd = "mknod /dev/megadev0 c %s 2" % major_number
    print("running in shell: %s" % cmd, file=sys.stderr)
    try:
        result, output = getstatusoutput(cmd)
        if result != 0:
            end(UNKNOWN, "Error making device node '%s' - %s" \
                                                        % (devicenode, output))
        print("%s" % output, file=sys.stderr)
        print("now continuing with raid checks...", file=sys.stderr)
    except OSError as error:
        end(UNKNOWN, "Error making '%s' device node - %s" % (devicenode, error))


if os.geteuid() != 0:
    end(UNKNOWN, "You must be root to run this plugin")

if not os.path.exists(BIN):
    end(UNKNOWN, "Lsi MegaRaid utility '%s' was not found" % BIN)

if not os.access(BIN, os.X_OK):
    end(UNKNOWN, "Lsi MegaRaid utility '%s' is not executable" % BIN)

if not os.path.exists(MEGADEV):
    print("Megaraid device node not found (possible first " \
                       + "run?), creating it now...", file=sys.stderr)
    make_megadev(MEGADEV)


def run(args):
    """run megarc.bin util with passed in args and return output"""
    if not args:
        print("UNKNOWN: internal python error", end=' ')
        print("- no cmd supplied for Lsi MegaRaid utility")
        sys.exit(UNKNOWN)
    cmd = "%s %s -nolog" % (BIN, args)
    result, output = getstatusoutput(cmd)
    lines = output.split("\n")
    if result != 0:
        if lines[0][-25:] == "No such file or directory":
            end(UNKNOWN, "Cannot find Lsi MegaRaid utility '%s'" % BIN)
        elif not lines:
            end(UNKNOWN, "No output from Lsi MegaRaid utility")
        elif len(lines) < 13:
            print("Error running '%s':" % cmd, file=sys.stderr)
            print("%s" % output, file=sys.stderr)
            end(UNKNOWN, "Output from Lsi MegaRaid utility is too short, " \
                       + "try -vvv for debug")
        else:
            end(UNKNOWN, "Error using MegaRaid utility - %s" \
                                                    % output.replace("\n", "|"))

    return lines


def get_controllers(verbosity):
    """finds and returns a list of all controllers on the local machine"""

    lines = run("-AllAdpInfo")

    if lines[11].strip() == "No Adapters Found":
        end(WARNING, "No LSI adapters were found on this machine")

    controllers = []
    controller_lines = lines[12:]
    for line in controller_lines:
        try:
            controller = int(line.split("\t")[1])
        except OSError as error:
            end(UNKNOWN, "Exception occurred in code - %s" % str(error))
        controllers.append(controller)

    if not controllers:
        end(WARNING, "No LSI controllers were found on this machine")

    if verbosity >= 2:
        print("Found %s controller(s)" % len(controllers))

    return controllers


def test_raid(verbosity, no_summary=False):
    """tests all raid arrays on all Lsi controllers found on local machine
    and returns status code"""

    status = OK
    message = ""
    number_arrays = 0
    non_optimal_arrays = 0
    controllers = get_controllers(verbosity)
    number_controllers = len(controllers)
    for controller in controllers:
        detailed_output = run("-dispCfg -a%s" % controller)
        if verbosity >= 3:
            for line in detailed_output:
                print("%s" % line)
            print()
        array_details = {}
        for line in detailed_output:
            if "Status:" in line:
                state = line.split(":")[-1][1:-1]
                logical_drive = line.split()[3][:-1]
                array_details[logical_drive] = [state]
            if "RaidLevel:" in line:
                raid_level = line.split()[3]
                array_details[logical_drive].append(raid_level)

        if not array_details:
            message += "No arrays found on controller %s. " % controller
            if status == OK:
                status = WARNING
            continue

        array_keys = list(array_details.keys())
        array_keys.sort()
        number_arrays += len(array_keys)

        for drive in array_keys:
            state = array_details[drive][0]
            if state != "OPTIMAL":
                non_optimal_arrays += 1
                raid_level = array_details[drive][1]
                # The Array number here is incremented by one because of the
                # inconsistent way that the LSI tools count arrays.
                # This brings it back in line with the view in the bios
                # and from megamgr.bin where the array counting starts at
                # 1 instead of 0
                message += 'Array %s status is "%s"' % (int(drive)+1, state)
                message += '(Raid-%s on adapter %s), ' \
                                                  % (raid_level, controller)
                status = CRITICAL


    message = add_status_summary(status, \
                          message, \
                          non_optimal_arrays)

    message = message.rstrip(" ")
    message = message.rstrip(",")

    if not no_summary:
        message = add_checked_summary(message, \
                              number_arrays, \
                              number_controllers)
    return status, message


def add_status_summary(status, message, non_optimal_arrays):
    """Add initial summary information on the overall state of the arrays"""

    if status == OK:
        message += "All arrays OK"
    else:
        if non_optimal_arrays == 1:
            message = "%s array not OK - " % non_optimal_arrays \
                    + message
        else:
            message = "%s arrays not OK - " % non_optimal_arrays \
                    + message
    return message


def add_checked_summary(message, number_arrays, number_controllers):
    """ Adds ending summary information on how many arrays were checked"""

    message += " [%s array" % number_arrays
    if number_arrays != 1:
        message += "s"
    message += " checked on %s controller" % number_controllers
    if number_controllers == 1:
        message += "]"
    else:
        message += "s]"
    return message


def main():
    """parses args and calls func to test raid arrays"""

    parser = OptionParser()
    parser.add_option("-n",
                      "--no-summary",
                      action="store_true",
                      dest="no_summary",
                      help="Do not display the number of arrays " \
                         + "checked. By default the number of arrays " \
                         + "checked are printed at the end of the " \
                         + "line. This is useful information and helps to " \
                         + "know that they are detected properly")

    parser.add_option("-v",
                      "--verbose",
                      action="count",
                      dest="verbosity",
                      help="Verbose mode. Good for testing plugin. By \
default only one result line is printed as per Nagios standards")

    parser.add_option("-V",
                      "--version",
                      action="store_true",
                      dest="version",
                      help="Print version number and exit")

    (options, args) = parser.parse_args()

    no_summary = options.no_summary
    verbosity = options.verbosity
    version = options.version

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    if version:
        print(__version__)
        sys.exit(OK)

    result, message = test_raid(verbosity, no_summary)

    end(result, message)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(CRITICAL)
