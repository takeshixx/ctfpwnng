_DEBUG=
_BASH_DEBUG=
_LIB_GAMESERVER_HOST=
_LIB_GAMESERVER_PORT=
_LIB_GAMESERVER_URL=
_LIB_GAMESERVER_SUBMIT_VIA_HTTP=
# --
_LIB_FLAG_REGEX="\w{31}="
_LIB_REGEX_IP="[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"
_LIB_GAMESERVER_TIMEOUT=".1"
_LIB_LOG_DIR="_logs"
_LIB_LOG_FILE="${_LIB_LOG_DIR}/ctfpwn.log"
_LIB_RUN_DIR="_run"
_LIB_REDIS_SOCKET="/run/redis/redis.sock"
_LIB_REDIS_FLAG_SET_UNPROCESSED="flags_unprocessed"
_LIB_REDIS_FLAG_SET_ACCEPTED="flags_accepted"
_LIB_REDIS_FLAG_SET_EXPIRED="flags_expired"
_LIB_REDIS_FLAG_SET_UNKNOWN="flags_unknown"
_LIB_REGEX_SUBMISSION_ACCEPTED="accept"
_LIB_REGEX_SUBMISSION_INVALID="invalid|not valid|unknown|your own|own flag|no such"
_LIB_REGEX_SUBMISSION_EXPIRED="expired|already submitted|too old"
_LIB_REGEX_SUBMISSION_DOWN="corresponding|service is down"
_LIB_PARALLEL_JOBS=150
_LIB_PARALLEL_TIMEOUT="250%"
_LIB_PARALLEL_LOOP_SLEEP=5
_LIB_PARALLEL=$(which parallel)

if [ -f "localconf.sh" ];then
    source localconf.sh
fi

if [ -n "$_BASH_DEBUG" ];then
    set -x
fi

# Print debug messages, most likely only
# relevant during development.
debug(){
    if [ -n "$_DEBUG" ];then
         _log "[d] $*"
    fi
}

# Log output to a logfile. Should be used
# to keep track of exploit iterations
# and stuff like that.
_log(){
    echo "[$(date +'%T')] ${*}" | tee -a "$_LIB_LOG_FILE"
}

log(){
    _log "[*] $*"
}

log_info(){
    _log "[+] $*"
}

log_error(){
    _log "[ERROR] $*"
}

log_warning(){
    _log "[WARNING] $*"
}

# Helper function to check if a variable
# is empty. Usefule for parsing service
# files and command line arguments.
is_var_empty(){
    if [ -z "$1" ];then
        # var is empty
        return 1
    else
        # var is not empty
        return 0
    fi
}

# This function saves flags to Redis. The
# Arguments:
#   SERVICE_NAME - The name of the corresponding
#                  service.
#   FLAGS        - A list of flags, one per
#                  line.
log_flags(){
    if [ $# -ne 2 ];then
        echo "Please provide the service name and flags to the log_flags function!"
        exit
    fi
    SERVICE_NAME="$1"
    FLAGS=$(echo -e "$2" |grep -Pio "$_LIB_FLAG_REGEX")
    if [ -n "$FLAGS" ];then
        while read flag;do
            redis_client HMSET "$flag" service "$SERVICE_NAME" timestamp "$(date +%s)" >/dev/null
            redis_client SADD flags_unprocessed "$flag" >/dev/null
        done <<< "$FLAGS"
    fi
}

# Check if the flag has already been processed,
# e.g. if it has been accepted, expired or
# not a valid flag at all. Should be used to
# prevent submitting flags multiple times.
# Arguments:
#   FLAG - The flag that should be checked.
flag_already_processed(){
    FLAG=$1
    if [ -z "$FLAG" ];then
        log_warning "Please provide a flag"
        return
    fi
    retval=$(echo -e "SISMEMBER ${_LIB_REDIS_FLAG_SET_ACCEPTED} ${FLAG}\nSISMEMBER ${_LIB_REDIS_FLAG_SET_EXPIRED} ${FLAG}\nSISMEMBER ${_LIB_REDIS_FLAG_SET_UNKNOWN} ${FLAG}" | redis-cli -s "$_LIB_REDIS_SOCKET" --raw)
    if echo "$retval" |grep -q 1;then
        # Flag has already been processed
        return 0
    else
        # Flag has not yet been processed
        return 1
    fi
}

# Generic function for Redis interaction.
# Arguments:
#   REDIS_CMD - Whatever will be passed
#               to this function will be
#               interpreted as a Redis
#               query.
redis_client(){
    redis-cli -s "$_LIB_REDIS_SOCKET" --raw "$@"
}

# Check if a given file descriptor exists.
check_file_descriptor(){
    FD="$1"
    rco="$(true 2>/dev/null >&"${FD}"; echo $?)"
    rci="$(true 2>/dev/null <&"${FD}"; echo $?)"
    if [[ "${rco}${rci}" = "11" ]] ; then
        # FD is not readable/writable
        return 1
    else
        # FD is readable/writable
        return 0
    fi
}

# This function will submit unprocessed flags
# from Redis to the gameserver. It will take
# care to move the accepted/expired/unknown
# flags to the corresponding Redis sets.
submit_flags(){
    flags_unprocessed=$(redis_client SMEMBERS "$_LIB_REDIS_FLAG_SET_UNPROCESSED" | tr " " "\n")
    flag_count=$(echo -e "${flags_unprocessed}" | wc -l)
    flag_count=$((flag_count-1))
    if [ -z "$flag_count" -o "$flag_count" -eq 0 ];then
        log "No unprocessed flags found"
        return
    else
        log_info "Trying to process ${flag_count} flag(s)"
    fi
    if [ -n "$_LIB_GAMESERVER_SUBMIT_VIA_HTTP" ];then
        if [ -z "$_LIB_GAMESERVER_URL" ];then
            log_error "_LIB_GAMESERVER_URL not set!"
            exit 1
        fi
        submit_flags_http "$flags_unprocessed"
    else
        if [ -z "$_LIB_GAMESERVER_HOST" -o -z "$_LIB_GAMESERVER_PORT" ];then
            log_error "_LIB_GAMESERVER_HOST or _LIB_GAMESERVER_PORT not set!"
            exit 1
        fi
        submit_flags_tcp "$flags_unprocessed"
    fi
}

submit_flags_tcp(){
    flags_unprocessed="$1"
    if ! exec 666<>"/dev/tcp/${_LIB_GAMESERVER_HOST}/${_LIB_GAMESERVER_PORT}";then
        log_error "Gameserver TCP connection refused on port ${_LIB_GAMESERVER_PORT}! Postponing flag submission."
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
                redis_client SREM "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$flag"
                continue
            fi
            echo "$flag" >&666
            retval=$(timeout "$_LIB_GAMESERVER_TIMEOUT" cat <&666)
            if echo "${retval}" | grep -Piq "${_LIB_REGEX_SUBMISSION_ACCEPTED}";then
                debug "Flag ${flag} has been accepted."
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_ACCEPTED" "$flag" >/dev/null
                success_count=$((success_count+1))
            elif echo "${retval}" | grep -Piq "${_LIB_REGEX_SUBMISSION_INVALID}";then
                debug "Flag ${flag} is not valid!"
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_UNKNOWN" "$flag" >/dev/null
            elif echo "${retval}" | grep -Piq "${_LIB_REGEX_SUBMISSION_EXPIRED}";then
                debug "Flag ${flag} is expired!"
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_EXPIRED" "$flag" >/dev/null
            elif echo "${retval}" | grep -Piq "${_LIB_REGEX_SUBMISSION_DOWN}";then
                service_down=$(redis_client HMGET "${flag}" service)
                log_warning "Flag ${flag} cannot be submitted: service *${service_down}* is down!"
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

# RuCTFE 2017 introduced a HTTP-based
# flag submission. This function will
# process flags via the JSON API.
submit_flags_http(){
    flags_unprocessed="$1"
    flags_formatted="["
    while read flag;do
        if flag_already_processed "$flag";then
            redis_client SREM "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$flag" >/dev/null
            continue
        fi
        flags_formatted="${flags_formatted}\"${flag}\","
    done <<< "$flags_unprocessed"
    flags_formatted="${flags_formatted::-1}"
    flags_formatted="${flags_formatted}]"
    if [ -z "${_RUCTFE_TEAM_TOKEN}" ];then
        echo "RuCTFE Team Token not found!"
        return
    fi
    curl_out=$(curl -s -H "X-Team-Token: ${_RUCTFE_TEAM_TOKEN}" -X PUT -d "${flags_formatted}" "${_LIB_GAMESERVER_URL}")
    if [ -z "${curl_out}" ];then
        log_error "curl command did not return any output!"
        return
    fi
    success_count=0
    json_input=$(echo -e "${curl_out}" | jq -cr ".[]" 2>/dev/null)
    if [ -z "$json_input" ];then
        log_error "HTTP flag submission returned invalid response: ${curl_out}"
        return
    fi
    local msg
    local status
    local flag
    while read -r line;do
        msg=$(echo -e "${line}" | jq -r ".msg")
        status=$(echo "${line}" | jq -r ".status")
        flag=$(echo "${line}" | jq -r ".flag")
        if $status;then
            echo "${msg}"
            redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_ACCEPTED" "$flag" >/dev/null
            success_count=$((success_count+1))
        else
            echo "${msg}"
            if echo "${msg}" | grep -Piq "${_LIB_REGEX_SUBMISSION_INVALID}";then
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_UNKNOWN" "$flag" >/dev/null
            elif echo "${msg}" | grep -Piq "${_LIB_REGEX_SUBMISSION_EXPIRED}";then
                redis_client SMOVE "$_LIB_REDIS_FLAG_SET_UNPROCESSED" "$_LIB_REDIS_FLAG_SET_EXPIRED" "$flag" >/dev/null
            elif echo "${msg}" | grep -Piq "${_LIB_REGEX_SUBMISSION_DOWN}";then
                log_warning "Flag ${flag} cannot be submitted: service is down!"
            else
                log_error "Unknown flag state: ${msg}"
            fi
        fi
    done <<< "$json_input"
    if [ "$success_count" -gt 0 ];then
        log_info "Successfully submitted ${success_count} flag(s)."
    fi
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
        "$_LIB_PARALLEL" --jobs "${_LIB_PARALLEL_JOBS}" --timeout "${_LIB_PARALLEL_TIMEOUT}" -a targets/_all "/bin/bash -c 'cd exploits/${SERVICE}/; ./run.sh {}'" >> "$_LIB_LOG_FILE" &
        count=$((count+1))
    done
    log_info "Scheduled $((count*ips)) processes for ${count} exploit(s)."
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
    if ! which jq >/dev/null;then
        echo "jq not found!"
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
