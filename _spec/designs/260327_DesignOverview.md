# Ziprel Design Overview 

Ziprel is a minimalist tool for deploying Elixir Releases.

## Deploy Tool Comparison 

There are many deploy tools for Elixir Releases: 

- Kamal | Ruby Deploy Tool 
- Xamal | Elixir Deploy Tool
- Cogni | Bash Tool Generators

These tools are great for production deployment in commercial environments, at
the expense of complexity and learning-curve.

Ziprel Use Case:

- Deploy on LAN Host 
- Internal Apps, Prototyping 
- No Proxy, No SSL Provisioning 
- Run on ports other than port 80
- Single Server (mostly) 
- Service goes offline during Deploy

## Implementation 

Ziprel will be built a tech stack including:

- Elixir          | With common Elixir tooling
- Elixir MixTasks | The CLI for all interaction
- Elixir Releases | Self-contained packaging standard
- SSHex           | Elixir SSH package 
- Systemd         | The management tool on remote servers

```
Ziprel - Deploy Elixir releases to bare metal servers

Mix Tasks:
  mix ziprel                     This help message
  mix ziprel.init                Generate config stubs
  mix ziprel.sshcheck            Check SSH connection and permissions
  mix ziprel.setup               Setup servers and deploy
  mix ziprel.deploy              Deploy app to servers
  mix ziprel.versions            List release versions on servers
  mix ziprel.rollback [VERSION]  Rollback to a previous version
  mix ziprel.remove [VERSION]    Remove old releases
  mix ziprel.cleanup [SERVER]    Remove everything from server
```

**ziprel.init** 

- create a default config file in config/ziprel.yaml 
- create a systemd service file in priv/ziprel/<appname>.service

```yaml
servers: 
  - host1 
  - host2 
ssh:
  user: <name> 
```

The service file should be an EEX template.

**ziprel.sshcheck**

on all servers:
- test ssh connection 
- make sure the deploy user has sudo access 
- make sure the deploy user can create /opt/ziprel 

**ziprel.setup** 

for each server: 
- create service file /etc/systemd/services/<appname>.service
- create /opt/ziprel 
- deploy (see below)

**ziprel.deploy**
- generate a new release `MIX_ENV=prod mix release`

for each server:
- copy the tar file to the remote server /opt/ziprel/archives/<version>.tar 
- untar the release file into /opt/ziprel/releases/<version>
- set the symlink /opt/ziprel/current to point to /opt/ziprel/releases/<version>
- start or restart the service `sudo systemctl <appname> start`

**ziprel.versions** 

for each server: 
- ls /opt/ziprel/releases 

**ziprel.rollback**

get the <version> number

for each server:
- set the symlink /opt/ziprel/current to point to /opt/ziprel/releases/<version>
- restart the service `system systemctl <appname> restart`

**ziprel.remove** 

get the <version> number
do not remove current version

for each server:
- remove /opt/ziprel/releases/<version>
- remove /opt/ziprel/archives/<version>.tar 

**ziprel.cleanup**

for <server>:
- remove server from config/ziprel.yaml 
- remove service file 
- remove /opt/ziprel

