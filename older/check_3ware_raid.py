#!/usr/bin/env python3
#
#  Author: Hari Sekhon
#  Date: 2007-02-20 17:49:00 +0000 (Tue, 20 Feb 2007)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""Nagios plugin to test the state of all 3ware raid arrays and/or drives
   on all 3ware controllers on the local machine. Requires the tw_cli program
   written by 3ware, which should be called tw_cli_64 if running on a 64-bit
   system. May be remotely executed via any of the standard remote nagios
   execution mechanisms"""

from __future__ import print_function

import os
import re
import sys
from optparse import OptionParser
try:
    from subprocess import Popen, PIPE, STDOUT
except ImportError:
    print("Failed to import subprocess module.", end=' ')
    print("Perhaps you are using a version of python older than 2.4?")
    sys.exit(4)

__author__  = "Hari Sekhon"
__title__   = "Nagios Plugin for 3ware RAID"
__version__ = '1.2.1'

# Standard Nagios return codes
OK       = 0
WARNING  = 1
CRITICAL = 2
UNKNOWN  = 3

SRCDIR = os.path.dirname(sys.argv[0])


def end(status, message, disks=False):
    """Exits the plugin with first arg as the return code and the second
    arg as the message to output"""

    check = "RAID"
    if disks:
        check = "DISKS"
    if status == OK:
        print("%s OK: %s" % (check, message))
        sys.exit(OK)
    elif status == WARNING:
        print("%s WARNING: %s" % (check, message))
        sys.exit(WARNING)
    elif status == CRITICAL:
        print("%s CRITICAL: %s" % (check, message))
        sys.exit(CRITICAL)
    else:
        print("UNKNOWN: %s" % message)
        sys.exit(UNKNOWN)


if os.geteuid() != 0:
    end(UNKNOWN, "You must be root to run this plugin")

ARCH = os.uname()[4]

BIN = None

def _set_twcli_binary(path=None):
    """ set the path to the twcli binary"""
    global BIN

    if path:
        BIN = path
    elif re.match("i[3456]86", ARCH):
        BIN = SRCDIR + "/tw_cli"
    elif ARCH == "x86_64":
        BIN = SRCDIR + "/tw_cli_64"
    else:
        end(UNKNOWN, "architecture is not x86 or x86_64, cannot run 3ware " \
                     "utility")

    if not os.path.exists(BIN):
        end(UNKNOWN, "3ware utility for this architecture '%s' cannot be " \
                     "found" % BIN)

    if not os.access(BIN, os.X_OK):
        end(UNKNOWN, "3ware utility '%s' is not executable" % BIN)


def run(cmd):
    """runs a system command and returns stripped output"""
    if not cmd:
        end(UNKNOWN, "internal python error - " \
                   + "no cmd supplied for 3ware utility")
    try:
        process = Popen(BIN, stdin=PIPE, stdout=PIPE, stderr=STDOUT)
    except OSError as error:
        error = str(error)
        if error == "No such file or directory":
            end(UNKNOWN, "Cannot find 3ware utility '%s'" % BIN)
        else:
            end(UNKNOWN, "error trying to run 3ware utility - %s" % error)

    if process.poll():
        end(UNKNOWN, "3ware utility process ended prematurely")

    try:
        stdout, stderr = process.communicate(str.encode(cmd))
    except OSError as error:
        end(UNKNOWN, "unable to communicate with 3ware utility - %s" % error)


    if not stdout:
        end(UNKNOWN, "No output from 3ware utility")

    stdout = stdout.decode()
    output = str(stdout).split("\n")

    if output[1] == "No controller found.":
        end(UNKNOWN, "No 3ware controllers were found on this machine")

    stripped_output = output[3:-2]

    if process.returncode != 0:
        stderr = str(stdout).replace("\n"," ")
        end(UNKNOWN, "3ware utility returned an exit code of %s - %s" \
                                                 % (process.returncode, stderr))
    else:
        return stripped_output


def test_all(verbosity, warn_true=False, no_summary=False, show_drives=False):
    """Calls the raid and drive testing functions"""

    array_result, array_message = test_arrays(verbosity, warn_true, no_summary)

    drive_result, drive_message = test_drives(verbosity, warn_true, no_summary)

    if array_result != OK and drive_result == OK and not show_drives:
        return array_result, array_message

    if drive_result > array_result:
        result = drive_result
    else:
        result = array_result

    if drive_result != OK:
        if array_result == OK:
            message = "Arrays OK but... " + drive_message
        else:
            message = array_message + ", " + drive_message
    else:
        if show_drives:
            message = array_message + ", " + drive_message
        else:
            message = array_message

    return result, message


def test_arrays(verbosity, warn_true=False, no_summary=False):
    """Tests all the raid arrays on all the 3ware controllers on
    the local machine"""

    lines = run("show")
    #controllers = [ line.split()[0] for line in lines ]
    controllers = [ line.split()[0] for line in lines if line and line[0] == "c" ]

    status = OK
    message = ""
    number_arrays = 0
    arrays_not_ok = 0
    number_controllers = len(controllers)
    for controller in controllers:
        unit_lines = run("/%s show unitstatus" % controller)
        if verbosity >= 3:
            for unit_line in unit_lines:
                print(unit_line)
            print()

        for unit_line in unit_lines:
            number_arrays += 1
            unit_line = unit_line.split()
            state = unit_line[2]
            if state == "OK":
                continue
            elif state == "REBUILDING"    or \
                 state == "VERIFY-PAUSED" or \
                 state == "VERIFYING"     or \
                 state == "INITIALIZING":

                unit = int(unit_line[0][1:])
                raid = unit_line[1]
                if state == "VERIFY-PAUSED" or \
                   state == "VERIFYING"     or \
                   state == "INITIALIZING":
                    percent_complete = unit_line[4]
                else:
                    percent_complete = unit_line[3]

                message += "Array %s status is '%s'(%s on adapter %s) - " \
                                          % (unit, state, raid, controller[1:])
                if state == "REBUILDING":
                    message += "Rebuild "
                elif state == "VERIFY-PAUSED" or state == "VERIFYING":
                    message += "Verify "
                elif state == "INITIALIZING":
                    message += "Initializing "
                message += "Status: %s%% complete, " % percent_complete
                if warn_true:
                    arrays_not_ok += 1
                    if status == OK:
                        status = WARNING
            else:
                arrays_not_ok += 1
                unit = int(unit_line[0][1:])
                raid = unit_line[1]
                message += "Array %s status is '%s'" % (unit, state)
                message += "(%s on adapter %s), " % (raid, controller[1:])
                status = CRITICAL

    message = message.rstrip(", ")

    message = add_status_summary(status, message, arrays_not_ok, "arrays")

    if not no_summary:
        message = add_checked_summary(message, \
                              number_arrays, \
                              number_controllers, \
                              "arrays")

    return status, message


def test_drives(verbosity, warn_true=False, no_summary=False):
    """Tests all the drives on the all the 3ware raid controllers
    on the local machine"""

    lines = run("show")
    controllers = []
    for line in lines:
        parts = line.split()
        if parts:
            controllers.append(parts[0])

    status = OK
    message = ""
    number_drives = 0
    drives_not_ok = 0
    number_controllers = len(controllers)
    for controller in controllers:
        drive_lines = run("/%s show drivestatus" % controller)
        number_drives += len(drive_lines)

        if verbosity >= 3:
            for drive_line in drive_lines:
                print(drive_line)
            print()

        for drive_line in drive_lines:
            drive_line = drive_line.split()
            state = drive_line[1]
            if state == "OK" or state == "NOT-PRESENT":
                continue
            if not warn_true and \
                state in ('VERIFYING', 'REBUILDING', 'INITIALIZING'):
                continue
            else:
                drives_not_ok += 1
                drive = drive_line[0]
                if drive[0] == "d":
                    drive = drive[1:]
                array = drive_line[2]
                if array[0] == "u":
                    array = array[1:]
                message += "Status of drive in port "
                message += "%s is '%s'(Array %s on adapter %s), " \
                                        % (drive, state, array, controller[1:])
                status = CRITICAL

    message = message.rstrip(", ")

    message = add_status_summary(status, message, drives_not_ok, "drives")

    if not no_summary:
        message = add_checked_summary(message, \
                              number_drives, \
                              number_controllers, \
                              "drives")

    return status, message


def add_status_summary(status, message, number_failed, device):
    """Adds a status summary string to the beginning of the message
    and returns the message"""

    if device == "arrays":
        if number_failed == 1:
            device = "array"
    elif device == "drives":
        if number_failed == 1:
            device = "drive"
    else:
        device = "[unknown devices, please check code]"

    if status == OK:
        if message == "":
            message = "All %s OK" % device + message
        else:
            message = "All %s OK - " % device + message
    else:
        message = "%s %s not OK - " % (number_failed, device) + message

    return message


def add_checked_summary(message, number_devices, number_controllers, device):
    """Adds a summary string of what was checked to the end of the message
    and returns the message"""

    if device == "arrays":
        if number_devices == 1:
            device = "array"
    elif device == "drives":
        if number_devices == 1:
            device = "drive"
    else:
        device = "[unknown devices, please check code]"

    if number_controllers == 1:
        controller = "controller"
    else:
        controller = "controllers"

    message += " [%s %s checked on %s %s]" % (number_devices, device, \
                                                number_controllers, controller)

    return message


def main():
    """Parses command line options and calls the function to
    test the arrays/drives"""

    parser = OptionParser()


    parser.add_option( "-a",
                       "--arrays-only",
                       action="store_true",
                       dest="arrays_only",
                       help="Only test the arrays. By default both arrays " \
                          + "and drives are checked")

    parser.add_option( "-b",
                       "--binary",
                       dest="binary",
                       help="Full path of the tw_cli binary to use.")

    parser.add_option( "-d",
                       "--drives-only",
                       action="store_true",
                       dest="drives_only",
                       help="Only test the drives. By default both arrays " \
                          + "and drives are checked")

    parser.add_option( "-n",
                       "--no-summary",
                       action="store_true",
                       dest="no_summary",
                       help="Do not display the number of arrays/drives " \
                          + "checked. By default the number of arrays and " \
                          + "drives checked are printed at the end of the " \
                          + "line. This is useful information and helps to " \
                          + "know that they are detected properly")

    parser.add_option( "-s",
                       "--show-drives",
                       action="store_true",
                       dest="show_drives",
                       help="Show drive status. By default drives are " \
                          + "checked as well as arrays, but there is no " \
                          + "output regarding them unless there is a " \
                          + "problem. Use this is you want drive details as " \
                          + "well when there is an array problem (default " \
                          + "behaviour is to only show the array problem to " \
                          + "avoid too much cluttering information), " \
                          + "or if you want to see the drive information " \
                          + "even when all drives are ok")

    parser.add_option( "-w",
                       "--warn-rebuilding",
                       action="store_true",
                       dest="warn_true",
                       help="Warn when an array or disk is Rebuilding, " \
                          + "Initializing or Verifying. You might want to do " \
                          + "this to keep a closer eye on things. Also, these " \
                          + "conditions can affect performance so you might " \
                          + "want to know this is going on. Default is to not " \
                          + "warn during these states as they are not usually " \
                          + "problems")

    parser.add_option( "-v",
                       "--verbose",
                       action="count",
                       dest="verbosity",
                       default=0,
                       help="Verbose mode. Good for testing plugin. By default\
 only one result line is printed as per Nagios standards")

    parser.add_option( "-V",
                       "--version",
                       action="store_true",
                       dest="version",
                       help="Print version number and exit")

    (options, args) = parser.parse_args()

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    arrays_only  = options.arrays_only
    binary       = options.binary
    drives_only  = options.drives_only
    no_summary   = options.no_summary
    show_drives  = options.show_drives
    warn_true    = options.warn_true
    verbosity    = options.verbosity
    version      = options.version

    if version:
        print(__version__)
        sys.exit(OK)

    if arrays_only and drives_only:
        print("You cannot use the -a and -d switches together, they are", end=' ')
        print("mutually exclusive\n")
        parser.print_help()
        sys.exit(UNKNOWN)
    elif arrays_only and show_drives:
        print("You cannot use the -a and -s switches together")
        print("No drive information can be printed if you only check arrays\n")
        parser.print_help()
        sys.exit(UNKNOWN)
    elif drives_only and warn_true:
        print("You cannot use the -d and -w switches together")
        print("Array warning states are invalid when testing only drives\n")
        parser.print_help()
        sys.exit(UNKNOWN)

    _set_twcli_binary(binary)

    if arrays_only:
        result, output = test_arrays(verbosity, warn_true, no_summary)
    elif drives_only:
        result, output = test_drives(verbosity, warn_true, no_summary)
        end(result, output, True)
    else:
        result, output = test_all(verbosity, warn_true, no_summary, show_drives)

    end(result, output)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(CRITICAL)
