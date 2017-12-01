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
    log "Exiting CTFPWN"
}

main(){
    log
    log "Starting CTFPWN"
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
            log_error "No targets found! Please run targets/run-targets.sh"
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
