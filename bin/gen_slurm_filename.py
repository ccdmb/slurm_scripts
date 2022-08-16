#!/usr/bin/env python3

import re
import sys
import os


def pad(val):
    def inner(match):
        if match.group('pad') is None:
            pad = 1
        else:
            pad = int(match.group('pad'))
        val_ = int(val)
        return f'{val_:0>{pad}}'
    return inner


sub = sys.argv[1]

if re.search(r'\\', sub) is not None:
    print(sub)
    sys.exit(0)

SLURM_ARRAY_JOB_ID = os.environ.get("SLURM_ARRAY_JOB_ID", 1)
SLURM_ARRAY_TASK_ID = os.environ.get("SLURM_ARRAY_TASK_ID", 2)
SLURM_JOB_ID = os.environ.get("SLURM_JOB_ID", 3)
SLURM_LOCALID = os.environ.get("SLURM_LOCALID", 4)
SLURM_NODENAME = os.environ.get("SLURM_NODENAME", "NODENAME")
SLURM_NODEID = os.environ.get("SLURM_NODEID", 5)
USER = os.environ.get("USER", "USER")
SLURM_JOB_NAME = os.environ.get("SLURM_JOB_NAME", "JOB_NAME")

sub = re.sub(r'(?<!%)%(?P<pad>\d+)?A', pad(SLURM_ARRAY_JOB_ID), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?a', pad(SLURM_ARRAY_TASK_ID), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?J', f"{SLURM_JOB_ID}.{SLURM_LOCALID}", sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?j', pad(SLURM_JOB_ID), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?N', SLURM_NODENAME, sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?n', pad(SLURM_NODEID), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?s', pad(SLURM_LOCALID), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?t', pad(SLURM_LOCALID), sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?u', USER, sub)
sub = re.sub(r'(?<!%)%(?P<pad>\d+)?x', SLURM_JOB_NAME, sub)
sub = re.sub(r'%%', r'%', sub)
print(sub)
