_DEBUG=true
_LIB_FLAG_REGEX="\w{31}="
_LIB_REGEX_IP="[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"
#_LIB_GAMESERVER_HOST=flags.ructfe.org
#_LIB_GAMESERVER_PORT=31337
_LIB_GAMESERVER_HOST=127.0.0.1
_LIB_GAMESERVER_PORT=9000
_LIB_GAMESERVER_TIMEOUT=.1
_LIB_LOG_DIR=_logs
_LIB_LOG_FILE="${_LIB_LOG_DIR}/ctfpwn.log"
_LIB_RUN_DIR=_run
_LIB_REDIS_SOCKET="/run/redis/redis.sock"
_LIB_REDIS_FLAG_SET_UNPROCESSED=flags_unprocessed
_LIB_REDIS_FLAG_SET_ACCEPTED=flags_accepted
_LIB_REDIS_FLAG_SET_EXPIRED=flags_expired
_LIB_REDIS_FLAG_SET_UNKNOWN=flags_unknown

# Print debug messages, most likely only
# relevant during development.
debug(){
    if [ -n "$_DEBUG" ];then
        echo "$*"
    fi
}

# Log output to a logfile. Should be used
# to keep track of exploit iterations
# and stuff like that.
log(){
    echo "[$(date)] ${*}" >> $_LIB_LOG_FILE
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

log_flags(){
    if [ $# -ne 2 ];then
        echo "Please provide the service name and flags to the log_flags function!"
        exit
    fi
    SERVICE_NAME=$1
    FLAGS=$2
    if [ -n "$_FLAGS" ];then
        while read flag;do
            redis_client HMSET $flag service $SERVICE_NAME timestamp $(date +%s) >/dev/null
            redis_client SADD flags_unprocessed $flag >/dev/null
        done <<< "$FLAGS"
    fi
}

# Check if the flag has already been processed,
# e.g. if it has been accepted, expired or
# not a valid flag at all.
flag_already_processed(){
    FLAG=$1
    if [ -z "$FLAG" ];then
        echo "Please provide a flag"
        return
    fi
    retval=$(echo -e "SISMEMBER ${_LIB_REDIS_FLAG_SET_ACCEPTED} ${FLAG}\nSISMEMBER ${_LIB_REDIS_FLAG_SET_EXPIRED} ${FLAG}\nSISMEMBER ${_LIB_REDIS_FLAG_SET_UNKNOWN} ${FLAG}" | redis-cli -s "$_LIB_REDIS_SOCKET" --raw)
    if $(echo "$retval" |grep 1);then
        # Flag has already been processed
        return 0
    else
        # Flag has not yet been processed
        return 1
    fi
}

# Generic function for Redis interaction.
redis_client(){
    redis-cli -s "$_LIB_REDIS_SOCKET" --raw $*
}
