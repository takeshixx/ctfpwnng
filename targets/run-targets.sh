#!/bin/bash
script=${0##*/}
if [ $# -lt 1 ];then
    echo "Usage: ${script} <target network>" >&2
    echo "Example: ${script} 10.20.1.100/24" >&2
    exit 2
fi
TARGETRANGE=$1
if ! which nmap >/dev/null;then
    echo "Nmap not found!"
    exit 1
else
    if ! getcap "$(which nmap)" | grep -q "cap_net_bind_service,cap_net_admin,cap_net_raw+eip";then
        echo "Please set the capabilities or run this script with root privileges."
        echo "E.g.: setcap cap_net_bind_service,cap_net_admin,cap_net_raw+eip $(which nmap)"
    fi
fi
# RuCTFE 2017
#nmap -sS --open -oG _current -p22,7483,30303,8080,14473,8081,8082,4280 $TARGETRANGE
nmap -sS --open -oG _current -p22,80,8080 $TARGETRANGE
