#!/usr/bin/env python3

import re
from os.path import basename, dirname, splitext
import sys

REGEX = re.compile(r"(?<!{){(?P<index>\\d*)(?P<cmd>[^{}]*)}(?!})")

def parse_strip(cmd):
    flag = cmd[0]

    if flag == "l":
        start = "^"
        end = ""
    else:
        assert flag == "r"
        end = "$"
        start = ""

    cmd = cmd[1:]
    strip_match = re.search(
        r"(?P<sep>[/%&~-_])(?P<pattern>.*)(?P=sep)",
        cmd
    )

    pattern = strip_match.group("pattern")
    if pattern is None:
        raise ValueError("Pattern didn't match the string.")

    PATTERN_REGEX = re.compile(
        start +
        "(?P<pattern>" +
        pattern +
        ")" +
        end
    )
    cmd = cmd[pattern.endpos:]

    def inner(s):
        match_ = PATTERN_REGEX.search(s)

        start, end = match_.span("pattern")
        if flag == "l":
            return s[end:]
        else:
            return s[:start]

    return inner, cmd


def parse_sub(cmd):
    sub_match = re.search(
        r"(?P<sep>[/%&~-_])(?P<pattern>.*)(?P=sep)(?P<repl>.*)(?P=sep)",
        cmd
    )

    if pattern is None:
        raise ValueError("Pattern didn't match the string.")

    pattern = sub_match.group("pattern")

    repl_ = sub_match.group("repl")
    PATTERN_REGEX = re.compile(pattern)

    cmd = cmd[pattern.endpos:]

    def inner(s):
        match_ = PATTERN_REGEX.sub(s, repl_)
        return match_

    return inner, cmd


def parse_cmd(cmd):
    cmd = cmd.strip()
    if cmd == "":
        return (lambda x: x), None
    elif cmd.startswith("b"):
        return basename, cmd[1:]
    elif cmd.startswith("d"):
        return dirname, cmd[1:]
    elif cmd.startswith("e"):
        return splitext, cmd[1:]
    elif cmd.startswith("l") or cmd.startswith("r"):
        return parse_strip(cmd)
    elif cmd.startswith("s"):
        cmd = cmd[1:]
        return parse_sub(cmd)
    else:
        raise ValueError("Got unknown command")


def parse_array(cmd):
    return


def outer(nparams, line):
    def replacement(match):
        if (match.group("index") == "") and (nparams > 1):
            raise ValueError(
                "If using replacement strings with more than 1 "
                "parameter, the patterns must have an index."
            )

        index = match.group("index")
        if index == "":
            index = 0
        else:
            index = int(index) - 1

        val = line[index]
        cmd = match.group("cmd")
        if cmd == "":
            return val

        if "//" in cmd:
            return dirname(val)
        elif "/" in cmd:
            val = basename(val)

        for i in range(cmd.count(".")):
            val, _ = splitext(val)
        return val
    return replacement

for line in sys.stdin:
    line = line.strip().split()
    if len(line) == 0:
        continue
    nparams = int(sys.argv[1])
    command = sys.argv[2]
    assert len(line) == nparams, line
    fn = outer(nparams, line)
    cmd = REGEX.sub(fn, command)
    if cmd == command:
        cmd = cmd + " '" + "' ".join(line) + "'"

    cmd = re.sub(r"(?P<paren>[{}])(?P=paren)", r"\\g<paren>", cmd)

    print(cmd)
