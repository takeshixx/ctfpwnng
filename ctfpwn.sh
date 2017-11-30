#!/bin/bash
# Enable exit on error
#set -e
# Enable debug output
#set -x
trap do_exit EXIT TERM
source lib.sh

_PARALLEL_JOBS=150
_PARALLEL_TIMEOUT="250%"
_PARALLEL_LOOP_SLEEP=5
_PARALLEL=$(which parallel)

# The cleanup function that will be
# called whenever this script exists.
do_exit(){
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
            log_error "exploits/${SERVICE}/run.sh is not executable!"
            continue
        fi
        log_info "Spawing ${SERVICE} (exploits/${SERVICE}/run.sh)"
        "$_PARALLEL" --jobs "$_PARALLEL_JOBS" --timeout "${_PARALLEL_TIMEOUT}" -a targets/_all "/bin/bash -c 'cd exploits/${SERVICE}/; ./run.sh {}'" >> "$_LIB_LOG_FILE" &
        count=$((count+1))
    done
    log_info "Scheduled $((count*ips)) processes for ${count} exploit(s)."
}

# This function will submit unprocessed flags
# from Redis to the gameserver. It will take
# care to move the accepted/expired/unknown
# flags to the corresponding Redis sets.
submit_flags(){
    flags_unprocessed=$(redis_client SMEMBERS "$_LIB_REDIS_FLAG_SET_UNPROCESSED" | tr " " "\n")
    log_info "Trying to process $(echo -e "${flags_unprocessed}" | wc -l) flag(s)"
    if [ -z "$flags_unprocessed" ];then
        log "No unprocessed flags found"
        return
    fi
    if ! exec 666<>/dev/tcp/localhost/9000;then
        log_error "Gameserver connection refused! Postponing flag submission."
        return
    fi
    if ! command >&666; then
        log_error "Flag submission FD 666 is not writable!"
        return
    fi
    # Read the welcome banner
    timeout "$_LIB_GAMESERVER_TIMEOUT" cat <&666 >/dev/null
    success_count=0
    # Loop as long as the FD is writable
    #while command >&666 2>&1 >/dev/null;do
    while check_file_descriptor 666;do
        while read flag;do
            if flag_already_processed "$flag";then
                redis_client SREM "$_LIB_REDIS_FLAG_SET_UNPROCESSED" $flag
                continue
            fi
            echo "$flag" >&666
            retval=$(timeout "$_LIB_GAMESERVER_TIMEOUT" cat <&666)
            if echo "$retval" | grep -Piq "accept";then
                debug "Flag ${flag} has been accepted."
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_ACCEPTED" "$flag" >/dev/null
                success_count=$((success_count+1))
            elif echo "$retval" | grep -Piq "invalid|not valid|unknown|own flag|no such";then
                debug "Flag ${flag} is not valid!"
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_UNKNOWN" "$flag" >/dev/null
            elif echo "$retval" | grep -Piq "expired";then
                debug "Flag ${flag} is expired!"
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_EXPIRED" "$flag" >/dev/null
            elif echo "$retval" | grep -Piq "corresponding|down";then
                debug "Flag ${flag} cannot be submitted: service is down!"
            else
                log_error "Unknown flag state: ${retval}"
            fi
        done <<< "$flags_unprocessed"
        # Close the FD/socket
        exec 666<&-
    done
    if [ "$success_count" -gt 0 ];then
        log_info "Successfully submitted ${success_count} flag(s)."
    fi
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
        if ! getcap "$(which nmap)" | grep -q "cap_net_bind_service,cap_net_admin,cap_net_raw+eip";then
            echo "Capabilities for Nmap not set! May requires to run run-targets.sh with root privileges."
        fi
    fi
    if [ ! -d "$_LIB_LOG_DIR" ];then
        echo "${_LIB_LOG_DIR} not found, creating it."
        mkdir -p "$_LIB_LOG_DIR"
    fi
    if [ ! -d "$_LIB_RUN_DIR" ];then
        echo "${_LIB_RUN_DIR} not found, creating it."
        mkdir -p "$_LIB_RUN_DIR"
    fi
}

main(){
    echo "Starting CTFPWN"
    check_dependencies
    echo "Dependency check passed"
    while true;do
        log
        log "---------------------"
        log
        debug "Preparing target list"
        if [ -f targets/_current ];then
            cat targets/_current | tail -n +2 | grep -P "$_LIB_REGEX_IP" | grep -i open | awk '{print $2}' > targets/_all
        else
            echo "No targets found! Please run targets/run.sh"
            exit 1
        fi
        log "Spawning exploits"
        run_exploits
        log "Waiting for background jobs"
        wait
        log "Scheduling flag submission"
        submit_flags &
        log "Run finished, sleeping for ${_PARALLEL_LOOP_SLEEP} secs"
        sleep "$_PARALLEL_LOOP_SLEEP"
    done
}

main
