#!/bin/bash
# Enable exit on error
#set -e
# Enable debug output
#set -x
trap do_exit EXIT TERM
source lib.sh

# The cleanup function that will be
# called whenever this script exists.
do_exit(){
    exec 666<&-
    log "Exiting CTFPWN"
}

main(){
    log
    log "Starting CTFPWNng"
    log
    check_dependencies
    debug "Dependency check passed"
    local counter=1
    while true;do
        log "Starting run ${counter}"
        counter=$((counter+1))
        log
        log "---------------------"
        log
        debug "Preparing target list"
        if [ -s targets/_current ];then
            log "Found $(wc -l targets/_current | awk '{print $1}') targets"
            cat targets/_current | tail -n +2 | grep -P "$_LIB_REGEX_IP" | grep -i open | awk '{print $2}' > targets/_all
        else
            log_error "No targets found! Please run targets/run-targets.sh"
            exit 1
        fi
        log "Spawning exploits"
        run_exploits
        log "Waiting for background jobs"
        wait
        log "Scheduling flag submission"
        submit_flags &
        log "Run finished, sleeping for ${_LIB_PARALLEL_LOOP_SLEEP} secs"
        sleep "$_LIB_PARALLEL_LOOP_SLEEP"
    done
}

main
