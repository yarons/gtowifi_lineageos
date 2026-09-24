#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
"""Battery level per plugged / unplugged period, with the drain rate and the screen-on time, from
Android's battery history:

    adb shell dumpsys batterystats --history > history.txt
    tools/battery-history.py history.txt

A period without the screen on is the standby drain of the build.
"""
import datetime
import re
import sys

LINE = re.compile(r'\s+(\d\d-\d\d \d\d:\d\d:\d\d)\.\d+ (\d{3})(.*)')


def when(stamp, year):
    return datetime.datetime.strptime(f'{year}-{stamp}', '%Y-%m-%d %H:%M:%S')


def main(path, year=datetime.date.today().year):
    periods, plug, screen_on_since = [], None, None
    for line in open(path, errors='replace'):
        match = LINE.match(line)
        if not match:
            continue
        stamp, level, rest = match.groups()
        now, level = when(stamp, year), int(level)
        found = re.search(r'plug=(\w+)', rest)
        state = found.group(1) if found else plug
        if '-plugged' in rest:
            state = 'none'
        if state != plug or not periods:
            # screen time that straddles the change belongs to both periods, each its own part
            if periods and screen_on_since is not None:
                periods[-1]['screen'] += (now - screen_on_since).total_seconds()
                screen_on_since = now
            periods.append(dict(start=now, end=now, plug=state, first=level, last=level, screen=0.0))
            plug = state
        period = periods[-1]
        period['end'], period['last'] = now, level
        if '+screen' in rest and screen_on_since is None:
            screen_on_since = now
        if '-screen' in rest and screen_on_since is not None:
            period['screen'] += (now - screen_on_since).total_seconds()
            screen_on_since = None
    if periods and screen_on_since is not None:
        periods[-1]['screen'] += (periods[-1]['end'] - screen_on_since).total_seconds()
    for p in periods:
        hours = (p['end'] - p['start']).total_seconds() / 3600
        if hours < 0.25:
            continue
        rate = (p['last'] - p['first']) / hours
        print(f"{p['start']:%m-%d %H:%M} -> {p['end']:%m-%d %H:%M}  {p['plug'] or '?':5} "
              f"{p['first']:3}% -> {p['last']:3}%  {hours:5.1f} h  {rate:+5.2f} %/h  "
              f"screen on {p['screen'] / 3600:4.1f} h")


if __name__ == '__main__':
    main(*sys.argv[1:2])
