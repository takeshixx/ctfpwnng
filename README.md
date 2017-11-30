# CTFPWNng

Next-gen automation framework for attack-defense CTFs.

## Dependencies

* Redis (redis-server and redis-cli)
* Nmap
* GNU parallel

## Usage

```
./ctfpwn.sh
```

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
