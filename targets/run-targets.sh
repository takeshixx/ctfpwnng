#!/bin/bash
script=${0##*/}
if [ $# -lt 1 ];then
    echo "Usage: ${script} <target network>" >&2
    echo "Example: ${script} 10.20.1.100/24" >&2
    exit 2
fi
TARGETRANGE=$1
nmap -sS --open -oG _current -p22,80,443,8080 $TARGETRANGE
