#!/usr/bin/env python3

import re
from os.path import basename, dirname, splitext, commonprefix
import sys

import argparse

__version__ = "0.0.1"


REGEX = re.compile(r"(?<!{){(?P<index>\d+)?(?P<arr>@)?(?P<cmd>[^{}]*)}(?!})")


def cli(prog, args):
    parser = argparse.ArgumentParser(
        prog=prog,
        description="Project description."
        )

    parser.add_argument(
        "-p", "--nparams",
        default=1,
        type=int,
        help="How many parameters do you expect?",
    )
    parser.add_argument(
        "-g", "--group",
        default=None,
        type=str,
        help="Should we group results somehow?",
    )

    parser.add_argument(
        "-f", "--file",
        default=None,
        type=argparse.FileType('r'),
        help=(
            "Instead of reading the files as arguments, "
            "take them from a file. Use '-' for stdin."
        )
    )

    parser.add_argument(
        "-o", "--outfile",
        default=sys.stdout,
        type=argparse.FileType('w'),
        help=(
            "Write commands here. Use '-' for stdout."
        )
    )

    # This is also a special action, that just prints the software name and
    # version, then exits.
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s " + __version__
    )

    parser.add_argument(
        "pattern",
        type=str,
        help="What pattern should we insert values into?"
    )

    parser.add_argument(
        "glob",
        type=str,
        nargs="*",
        help="Glob"
    )

    return parser.parse_args(args)


def flatten_lists(li):
    flat = []

    for k in li:
        if isinstance(k, str):
            flat.append(k)
        else:
            flat.extend(flatten_lists(k))
    return flat


def parse_slice(cmd):
    splice_match = re.search(
        r"^\s*(?P<start>\d+)?\s*:\s*(?P<end>\d+)",
        cmd
    )
    pos_match = re.search(
        r"^\s*(?P<pos>\d+)",
        cmd
    )

    if splice_match is not None:
        start = splice_match.group("start")
        end = splice_match.group("end")

        cmd = cmd[splice_match.end():]

        if start is not None:
            start = int(start)
            assert start >= 0
            start -= 1

        if end is not None:
            end = int(end)
            assert end > 0
            if start is not None:
                assert end > start

        indexer = slice(start, end)
        is_str = False

    elif pos_match is not None:
        pos = pos_match.group("pos")
        cmd = cmd[pos_match.end():]

        assert pos is not None
        indexer = int(pos)
        indexer -= 1
        is_str = True

    else:
        raise ValueError("Indexer match couldn't find a slice or pos")

    return (lambda x: x[indexer]), cmd, is_str


def parse_filter(cmd):
    filter_match = re.search(
        r"(?P<sep>[/%&~])(?P<pattern>.*)(?P=sep)",
        cmd
    )

    pattern = filter_match.group("pattern")
    if pattern is None:
        raise ValueError("Pattern didn't match the string.")

    PATTERN_REGEX = re.compile("(?P<pattern>" + pattern + ")")
    cmd = cmd[filter_match.end():]

    def inner(s):
        out = []
        for si in s:
            match_ = PATTERN_REGEX.search(si)
            if match_ is None:
                continue

            out.append(si)
        return out

    return inner, cmd, False


def parse_join(cmd):
    join_match = re.search(
        r"(?P<sep>[/%&~])(?P<pattern>.*)(?P=sep)",
        cmd
    )
    if join_match is None:
        raise ValueError("Pattern didn't match the string.")

    pattern = join_match.group("pattern")

    if pattern is None:
        raise ValueError("Pattern didn't match the string.")

    cmd = cmd[join_match.end():]

    def inner(s):
        return pattern.join(map(str, s))

    return inner, cmd, True


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
        r"(?P<sep>[/%&~])(?P<pattern>.*)(?P=sep)",
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
    cmd = cmd[strip_match.end():]

    def inner(s):
        match_ = PATTERN_REGEX.search(s)

        if match_ is None:
            return s

        start, end = match_.span("pattern")
        if flag == "l":
            return s[end:]
        else:
            return s[:start]

    return inner, cmd


def parse_sub(cmd):
    sub_match = re.search(
        r"(?P<sep>[/%&~])(?P<pattern>.*)(?P=sep)(?P<repl>.*)(?P=sep)",
        cmd
    )

    pattern = sub_match.group("pattern")

    if pattern is None:
        raise ValueError("Pattern didn't match the string.")

    repl_ = sub_match.group("repl")
    PATTERN_REGEX = re.compile(pattern)

    cmd = cmd[sub_match.end():]

    def inner(s):
        match_ = PATTERN_REGEX.sub(repl_, s)
        return match_

    return inner, cmd


def dirname2(s):
    s = dirname(s)
    if s == "":
        s = "./"
    return s


def parse_cmd(cmd):
    cmd = cmd.strip()
    if cmd == "":
        return (lambda x: x), None
    elif cmd.startswith("b"):
        return basename, cmd[1:]
    elif cmd.startswith("d"):
        return dirname2, cmd[1:]
    elif cmd.startswith("e"):
        return (lambda x: splitext(x)[0]), cmd[1:]
    elif cmd.startswith("l") or cmd.startswith("r"):
        return parse_strip(cmd)
    elif cmd.startswith("s"):
        cmd = cmd[1:]
        return parse_sub(cmd)
    else:
        raise ValueError(f"Got unknown command: '{cmd}'.")


def parse_arr_cmd(cmd):
    cmd = cmd.strip()

    if cmd == "":
        return (lambda x: x), None, False
    elif cmd.startswith(":"):
        cmd = cmd[1:]
        return parse_slice(cmd)
    elif cmd.startswith("f"):
        cmd = cmd[1:]
        return parse_filter(cmd)
    elif cmd.startswith("p"):
        cmd = cmd[1:]
        return commonprefix, cmd, True
    elif cmd.startswith("j"):
        cmd = cmd[1:]
        return parse_join(cmd)
    else:
        fn, cmd = parse_cmd(cmd)
        return (lambda x: list(map(fn, x))), cmd, False


def take_first(li):
    if len(li) > 0:
        return li[0]
    else:
        return li


def clean_array(li):
    if isinstance(li, str):
        return li
    elif isinstance(li, list):
        return " ".join(map(str, li))
    else:
        raise ValueError("What the heck are you doing?")


def parse_array(cmd):
    steps = []

    cmd = cmd.strip()
    while len(cmd) > 0:
        fn, cmd, is_str = parse_arr_cmd(cmd)
        steps.append(fn)

        if (cmd is None) or (cmd == ""):
            break

        cmd = cmd.strip()

        if is_str:
            steps.extend(parse_single(cmd))
            break

    steps.append(clean_array)
    return steps


def parse_single(cmd):

    steps = []
    cmd = cmd.strip()
    while len(cmd) > 0:
        fn, cmd = parse_cmd(cmd)
        steps.append(fn)

        if cmd is None:
            break

        cmd = cmd.strip()
    return steps


def outer(nparams, line):
    def replacement(match):
        if (match.group("index") == "") and (nparams > 1):
            raise ValueError(
                "If using replacement strings with more than 1 "
                "parameter, the patterns must have an index."
            )

        arr = match.group("arr")
        if arr == "":
            arr = None

        is_arr = arr is not None

        index = match.group("index")
        if (not is_arr) and ((index is None) or (index == "")):
            index = 0
            val = line[index]
        elif (index is None) or (index == ""):
            index = None
            val = flatten_lists(line)
        else:
            index = int(index)
            val = line[index]

        if not isinstance(val, str) and not is_arr:
            val = val[0]

        cmd = match.group("cmd")

        if is_arr:
            fns = parse_array(cmd)
        else:
            fns = parse_single(cmd)

        for fn in fns:
            val = fn(val)
        return str(val)
    return replacement


def get_index(njobs: int, p: int, i: int) -> int:
    return (i + (p * njobs))


def get_args(args: "list[str]", nparams: int):
    if len(args) == 0:
        raise ValueError("You haven't provided and files to operate on")

    if (len(args) % nparams) != 0:
        raise ValueError(
            "The number of files specified by your glob is not a "
            "multiple of your nparams."
        )

    out = []

    njobs = len(args) // nparams
    for i in range(njobs):
        row = []
        for p in range(nparams):
            index = get_index(njobs, p, i)
            row.append(args[index])
        out.append(row)
    return out


def get_args_from_file(handle, nparams: int):
    out = []
    for i, line in enumerate(handle, 1):
        line = line.strip()

        if line == "":
            continue

        line = line.split("\t")

        if len(line) != nparams:
            raise ValueError(
                f"The file doesn't have the specified number "
                f"of parameters ({nparams}) on line {i}."
            )

        out.append(line)
    return out


def group_by(groups, lines):
    out = dict()  # defaultdict(lambda: defaultdict(list))
    for group, line in zip(groups, lines):
        for i, value in enumerate(line):
            if group not in out:
                out[group] = [[] for _ in line]
            out[group][i].append(value)

    return list(out.values())


def get_groups(command, nparams, lines):
    groups = []

    for line in lines:
        fn = outer(nparams, line)
        cmd = REGEX.sub(fn, command)
        groups.append(cmd)
    return groups


def main():
    args = cli(prog=sys.argv[0], args=sys.argv[1:])
    if args.file is not None:
        lines = get_args_from_file(args.file, args.nparams)
    else:
        lines = get_args(args.glob, args.nparams)

    if args.group is not None:
        groups = get_groups(args.group, args.nparams, lines)
        lines = group_by(groups, lines)
    else:
        groups = None

    for line in lines:
        fn = outer(args.nparams, line)
        cmd = REGEX.sub(fn, args.pattern)
        if cmd == args.pattern:
            cmd = cmd + " '" + "' ".join(line) + "'"

        cmd = re.sub(r"(?P<paren>[{}])(?P=paren)", r"\g<paren>", cmd)
        print(cmd, file=args.outfile)
    return


if __name__ == "__main__":
    main()
