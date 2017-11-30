#!/bin/bash
# Enable exit on error
#set -e
# Enable debug output
#set -x
trap do_exit EXIT TERM
source lib.sh

_SEMAPHORE=$(mktemp -u "${_LIB_RUN_DIR}/sem.XXXXXXXX")
_PARALLEL_JOBS=10
_PARALLEL_LOOP_SLEEP=5
_PARALLEL=$(which parallel)

# The cleanup function that will be
# called whenever this script exists.
do_exit(){
    rm -rf ${_SEMAPHORE}
    exec 666<&-
    echo "Exiting CTFPWN"
}

# The main function for exploit scheduling.
# This function will start all the exploits
# that are not disabled (e.g. a .disabled
# file is present in the exploit directory
# or if the directory name starts with a
# underscore (_).
run_exploits(){
    count=0
    ips=$(wc -l targets/_all | awk '{print $1}')
    for SERVICE in $(ls exploits |grep -Pv "^_");do
        if [ -f "exploits/${SERVICE}/_disabled" ];then
            debug "exploits/${SERVICE} is disabled"
            continue
        fi
        if [ ! -x "exploits/${SERVICE}/run.sh" ];then
            echo "exploits/${SERVICE}/run.sh is not executable!"
            continue
        fi
        log "Spawing ${SERVICE} (exploits/${SERVICE}/run.sh)"
        $_PARALLEL --jobs $_PARALLEL_JOBS -a targets/_all "/bin/bash -c 'cd exploits/${SERVICE}/; ./run.sh {}'" >> $_LIB_LOG_FILE
        count=$((count+1))
    done
    log "Scheduled $((count*ips)) processes for ${count} exploits."
}

# This function will submit unprocessed flags
# from Redis to the gameserver. It will take
# care to move the accepted/expired/unknown
# flags to the corresponding Redis sets.
submit_flags(){
    flags_unprocessed=$(redis_client SMEMBERS "$_LIB_REDIS_FLAG_SET_UNPROCESSED" | tr " " "\n")
    log "Trying to process $(echo ${flags_unprocessed} | wc -l) flags"
    if [ -z "$flags_unprocessed" ];then
        echo "No unprocessed flags found"
        return
    fi
    if ! exec 666<>/dev/tcp/localhost/9000;then
        echo "Gameserver connection refused!"
        return
    fi
    if ! command >&666; then
        echo "Flag submission FD 666 is not writable!"
        return
    fi
    # Read the welcome banner
    timeout $_LIB_GAMESERVER_TIMEOUT cat <&666 >/dev/null
    # Loop as long as the FD is writable
    while command >&666;do
        while read flag;do
            if flag_already_processed "$flag";then
                redis_client SREM $_LIB_REDIS_FLAG_SET_UNPROCESSED $flag
                continue
            fi
            echo $flag >&666
            retval=$(timeout $_LIB_GAMESERVER_TIMEOUT cat <&666)
            if $(echo "$retval" | grep -Piq "accept");then
                debug "Flag ${flag} has been accepted."
                redis_client SMOVE $_LIB_REDIS_FLAG_SET_UNPROCESSED $_LIB_REDIS_FLAG_SET_ACCEPTED $flag >/dev/null
            elif $(echo "$retval" | grep -Piq "invalid|not valid|unknown|own flag|no such");then
                debug "Flag ${flag} is not valid!"
                redis_client SMOVE $_LIB_REDIS_FLAG_SET_UNPROCESSED $_LIB_REDIS_FLAG_SET_UNKNOWN $flag >/dev/null
            elif $(echo "$retval" | grep -Piq "expired");then
                debug "Flag ${flag} is expired!"
                redis_client SMOVE $_LIB_REDIS_FLAG_SET_UNPROCESSED $_LIB_REDIS_FLAG_SET_EXPIRED $flag >/dev/null
            elif $(echo "$retval" | grep -Piq "corresponding|down");then
                debug "Flag ${flag} cannot be submitted: service is down!"
            else
                log "Unknown flag state: ${retval}"
            fi
        done <<< "$flags_unprocessed"
        # Close the FD/socket
        exec 666<&-
    done
}

# Set capabilities for nmap/ncat. This is
# required to run SYN-scans or listen on
# low-range ports (<1024) without root
# privileges.
set_cap(){
    if [ $# -lt 1 ];then
        echo "Please provide a binary name."
        return
    fi
    if [ -f "$1" ];then
        BIN="$1"
    else
        BIN=$(which "$1")
    fi
    setcap cap_net_bind_service,cap_net_admin,cap_net_raw+eip "$BIN"
}

# Make sure everything we need is available.
check_dependencies(){
    if ! ps -p $$ -oargs= | grep -i bash >/dev/null;then
        echo "This script should run in bash!"
        exit 1
    fi
    if [ ! -S "$_LIB_REDIS_SOCKET" ];then
        echo "Redis socket ${_LIB_REDIS_SOCKET} not found!"
        exit 1
    fi
    if ! which redis-cli >/dev/null;then
        echo "redis-cli not found!"
        exit 1
    fi
    if ! which parallel >/dev/null;then
        echo "GNU parallel not found!"
        exit 1
    fi
    if ! which nmap >/dev/null;then
        echo "Nmap not found!"
        exit 1
    else
        if ! getcap $(which nmap) | grep -q "cap_net_bind_service,cap_net_admin,cap_net_raw+eip";then
            set_cap nmap
            set_cap ncat
        fi
    fi
    if [ ! -d "$_LIB_LOG_DIR" ];then
        echo "${_LIB_LOG_DIR} not found, creating it."
        mkdir -p $_LIB_LOG_DIR
    fi
    if [ ! -d "$_LIB_RUN_DIR" ];then
        echo "${_LIB_RUN_DIR} not found, creating it."
        mkdir -p $_LIB_RUN_DIR
    fi
}

main(){
    echo "Starting CTFPWN"
    check_dependencies
    echo "Dependency check passed"
    while true;do
        log "Preparing target list"
        if [ -f targets/_current ];then
            cat targets/_current | tail -n +2 | grep -P $_LIB_REGEX_IP | grep -i open | awk '{print $2}' > targets/_all
        else
            echo "No targets found! Please run targets/run.sh"
            exit
        fi
        log "Spawning exploits"
        run_exploits
        log "Waiting for jobs to be finished..."
        $_PARALLEL --semaphore --id "$_SEMAPHORE" --wait --bar >> $_LIB_LOG_FILE
        log "Scheduling flag submission"
        submit_flags &
        log "Run finished, sleeping for ${_PARALLEL_LOOP_SLEEP}"
        sleep $_PARALLEL_LOOP_SLEEP
    done
}

main
