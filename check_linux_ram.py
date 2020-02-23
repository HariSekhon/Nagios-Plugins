#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2007-02-25 22:58:59 +0000 (Sun, 25 Feb 2007)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""
Nagios plugin to check the amount of ram used on a Linux box. Takes in to
account cache and returns performance data for graphing as well.
"""

from __future__ import print_function

from sys import exit  # pylint: disable=redefined-builtin
from optparse import OptionParser

__author__ = "Hari Sekhon"
__title__ = "Nagios Plugin to check RAM used on Linux"
__version__ = "0.4.0"

# Standard Exit Codes for Nagios
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3


def check_ram(warning_threshold, critical_threshold, percent, verbosity, \
                                                                       nocache):
    """Takes warning and critical thresholds in KB or percentage if third
    argument is true, and returns a result depending on whether the amount free
    ram is less than the thresholds"""

    if verbosity >= 3:
        print("Opening /proc/meminfo")
    try:
        meminfo = open('/proc/meminfo')
    except IOError as _:
        print("RAM CRITICAL: Error opening /proc/meminfo - %s" % _)
        return CRITICAL

    output = meminfo.readlines()

    for line in output:
        cols = line.split()
        if cols[0] == "MemTotal:":
            memtotal = int(cols[1])
        elif cols[0] == "MemFree:":
            memfree = int(cols[1])
        elif cols[0] == "Cached:":
            memcached = int(cols[1])

    for _ in memtotal, memfree, memcached:
        if _ is None:
            print("UNKNOWN: failed to get mem stats")
            return UNKNOWN

    if nocache is True:
        total_free = memfree
    else:
        total_free = memfree + memcached

    total_used_megs = (memtotal - total_free) / 1024.0
    #total_free_megs = total_free / 1024.0
    memtotal_megs = memtotal / 1024.0

    if percent:
        warning_threshold_megs = \
                memtotal_megs * (100 - warning_threshold)  / 100.0
        critical_threshold_megs = \
                memtotal_megs * (100 - critical_threshold) / 100.0
    else:
        warning_threshold_megs = memtotal_megs - warning_threshold
        critical_threshold_megs = memtotal_megs - critical_threshold

    percentage_free = int(float(total_free) / float(memtotal) * 100)
    stats = "%d%% ram free (%d/%d MB used)" \
            % (percentage_free, total_used_megs, memtotal_megs) \
          + " | 'RAM Used'=%.2fMB;%.2f;%.2f;0;%.2f" % \
            (total_used_megs, warning_threshold_megs, critical_threshold_megs, \
             memtotal_megs)

    if percent is True:
        if percentage_free < critical_threshold:
            print("RAM CRITICAL:", end=' ')
            print("%s" % stats)
            return CRITICAL
        elif percentage_free < warning_threshold:
            print("RAM WARNING:", end=' ')
            print("%s" % stats)
            return WARNING
        print("RAM OK:", end=' ')
        print("%s" % stats)
        return OK
    else:
        if total_free < critical_threshold:
            print("RAM CRITICAL:", end=' ')
            print("%s" % stats)
            return CRITICAL
        if total_free < warning_threshold:
            print("RAM WARNING:", end=' ')
            print("%s" % stats)
            return WARNING
        print("RAM OK:", end=' ')
        print("%s" % stats)
        return OK


def main():
    """main func, parse args, do sanity checks and call check_ram func"""

    parser = OptionParser()

    parser.add_option("-n", "--no-include-cache",
                      action="store_true", dest="nocache",
                      help="Do not include cache as free ram. Linux tends to "
                      + "gobble up free ram as disk cache, but this is freely"
                      + " reusable so this plugin counts it as free space by "
                      + "default since this is nearly always what you want. "
                      + "This switch disables this behaviour so you use only "
                      + "the pure free ram. Not advised.")
    parser.add_option("-c", "--critical", dest="critical_threshold",
                      help="Critical threshold. Returns a critical status if "
                      + "the amount of free ram is less than this number. "
                      + "Specify KB, MB or GB after to specify units of "
                      + "KiloBytes, MegaBytes or GigaBytes respectively or % "
                      + "afterwards to indicate"
                      + "a percentage. KiloBytes is used if not specified")
    parser.add_option("-v", "--verbose", action="count", dest="verbosity",
                      help="Verbose mode. Good for testing plugin. By default"
                      + " only one result line is printed as per Nagios "
                      + "standards. Use multiple times for increasing "
                      + "verbosity (3 times = debug)")
    parser.add_option("-w", "--warning", dest="warning_threshold",
                      help="warning threshold. Returns a warning status if "
                      + "the amount of free ram "
                      + "is less than this number. Specify KB, MB or GB after"
                      + "to specify units of "
                      + "KiloBytes, MegaBytes or GigaBytes respectively or % "
                      + "afterwards to indicate a percentage. KiloBytes is "
                      + "used if not specified")

    options, args = parser.parse_args()

    # This script doesn't take any args, only options so we print
    # usage and exit if any are found
    if args:
        parser.print_help()
        return UNKNOWN

    nocache = False

    warning_threshold = options.warning_threshold
    critical_threshold = options.critical_threshold
    nocache = options.nocache
    verbosity = options.verbosity

    #==========================================================================#
    #                                Sanity Checks                             #
    #                  This is TOO big really but it allows for                #
    #                  nice flexibility on the command line                    #
    #==========================================================================#
    if warning_threshold is None:
        print("UNKNOWN: you did not specify a warning threshold\n")
        parser.print_help()
        return UNKNOWN
    elif critical_threshold is None:
        print("UNKNOWN: you did not specify a critical threshold\n")
        parser.print_help()
        return UNKNOWN
    else:
        warning_threshold = str(warning_threshold)
        critical_threshold = str(critical_threshold)

    megs = ["MB", "Mb", "mb", "mB", "M", "m"]
    gigs = ["GB", "Gb", "gb", "gB", "G", "g"]

    warning_percent = False
    critical_percent = False

    def get_threshold(threshold):
        """takes one arg and returns the float threshold value"""

        try:
            threshold = float(threshold)
        except ValueError:
            print("UNKNOWN: invalid threshold given")
            exit(UNKNOWN)

        return threshold

    # Find out if the supplied argument is a percent or a size
    # and get it's value
    if warning_threshold[-1] == "%":
        warning_threshold = get_threshold(warning_threshold[:-1])
        warning_percent = True
    elif warning_threshold[-2:] in megs:
        warning_threshold = get_threshold(warning_threshold[:-2]) * 1024
    elif warning_threshold[-1] in megs:
        warning_threshold = get_threshold(warning_threshold[:-1]) * 1024
    elif warning_threshold[-2:] in gigs:
        warning_threshold = get_threshold(warning_threshold[:-2]) * 1024 * 1024
    elif warning_threshold[-1] in gigs:
        warning_threshold = get_threshold(warning_threshold[:-1]) * 1024 * 1024
    else:
        warning_threshold = get_threshold(warning_threshold)

    if critical_threshold[-1] == "%":
        critical_threshold = get_threshold(critical_threshold[:-1])
        critical_percent = True
    elif critical_threshold[-2:] in megs:
        critical_threshold = get_threshold(critical_threshold[:-2]) * 1024
    elif critical_threshold[-1] in megs:
        critical_threshold = get_threshold(critical_threshold[:-1]) * 1024
    elif critical_threshold[-2:] in gigs:
        critical_threshold = get_threshold(critical_threshold[:-2]) * 1024 * \
                                                                            1024
    elif critical_threshold[-1] in gigs:
        critical_threshold = get_threshold(critical_threshold[:-1]) * 1024 * \
                                                                            1024
    else:
        critical_threshold = get_threshold(critical_threshold)

    # Make sure that we use either percentages or units but not both as this
    # makes the code more ugly and complex
    if warning_percent is True and critical_percent is True:
        percent_true = True
    elif warning_percent is False and critical_percent is False:
        percent_true = False
    else:
        print("UNKNOWN: please make thresholds either units or percentages, \
not one of each")
        return UNKNOWN

    # This assumes that the percentage units are numeric, which they must be to
    # have gotten through the get_threhold func above
    if warning_percent is True:
        if (warning_threshold < 0) or (warning_threshold > 100):
            print("warning percentage must be between 0 and 100")
            exit(WARNING)
    if critical_percent is True:
        if (critical_threshold < 0) or (critical_threshold > 100):
            print("critical percentage must be between 0 and 100")
            exit(CRITICAL)

    if warning_threshold <= critical_threshold:
        print("UNKNOWN: Critical threshold must be less than Warning threshold")
        return UNKNOWN

    # End of Sanity Checks

    result = check_ram(warning_threshold, critical_threshold, percent_true, \
                                                             verbosity, nocache)

    return result

if __name__ == "__main__":
    exit_code = main()
    exit(exit_code)
