# CTFPWNng

A simple framework that helps to automate execution of exploits for attack-defense CTFs. CTFPWNng schedules execution of exploits for all available/reachable targets and stores flags in a Redis queue. It also handles periodic submission of flags to the gameserver.

An exploit has three properties:

* Takes two positional arguments: an IP address and a port number of the target.
* Prints flags to stdout: the framework will grep for flags in the stdout data, which can include one or more flags or even other data.
* Is executable: an exploit can be written in any language or format as long as it is executable.

An exploit tries to get a flag/the flags from a single target system. The scheduling for all the other targets is handled by the framework.

## Dependencies

* Redis (redis-server and redis-cli)
* Nmap
* GNU parallel

## Configuration

Per-CTF configuration can be done in a local configuration file called `localconf.sh`. Variables for the whole framework can be overwritten in Bash syntax. The following `localconf.sh` shows a configuration example for a RuCTFE:

```
_LIB_GAMESERVER_HOST="flags.ructfe.org"
_LIB_GAMESERVER_PORT="31337"
_LIB_GAMESERVER_URL="http://monitor.ructfe.org/flags"
_RUCTFE_TEAM_TOKEN="900008d90-c13c-4242-a801-825558d222f7"
```

*Note*: The **_RUCTFE_TEAM_TOKEN** is provided in the `checker_token.txt` file that is included in the team configuration.

*Note*: RuCTFE allows to submit flags either via TCP (default) or HTTP. The following variable can be set to use HTTP submission:

```
_LIB_GAMESERVER_SUBMIT_VIA_HTTP=yes
```

## Usage

```
./ctfpwn.sh
```

*Note*: A deployment example is available in the [Vagrantfile](https://github.com/takeshixx/ctfpwnng/blob/master/Vagrantfile). It is recommended to always run CTFPWNng inside of a VM.

### Target Identification

The ```targets``` directory includes a wrapper script (```run-targets.sh```) that runs Nmap scans on the target range in order to identify alive hosts. This script should run regularly as a cronjob (TBD). Before ```ctfpwn.sh``` can be started, the script should run at least once to create a initial output file:

```
cd targets
./run-targets.sh
```

### Add Exploits

Adding a new exploit is as easy as copying the ```exploits/_template``` directory. The following example creates an exploit for a service called **wood**

```
cd ctfpwnng
cp -r exploits/_template exploits/wood
```

An exploit directory requires at least two files (already included in the ```exploits/_template``` directory):

* ```service```: A service definition file. This file must contain the **_SERVICE_NAME** and **_SERVICE_PORT** variables.
* ```run.sh```: The exploit wrapper script that either includes or starts the actual exploit code. It is also responsible for calling the ```log_flags()``` function that will add flags to the Redis database.

### Disable Exploits

Exploits can be disabled by either creating a ```.disabled``` file:

```
touch exploits/wood/.disabled
```

Or by preceeding the exploit directory name with an underscore:

```
mv exploits/wood exploits/_wood
```
