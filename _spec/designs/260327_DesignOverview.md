# Sysd Design Overview 

Sysd is a minimalist tool for deploying Elixir Releases.

## Deploy Tool Comparison 

There are many deploy tools for Elixir Releases: 

- Kamal | Ruby Deploy Tool 
- Xamal | Elixir Deploy Tool
- Cogni | Bash Tool Generators

These tools are great for production deployment in commercial environments, at
the expense of complexity and learning-curve.

Sysd Use Case:

- Deploy on LAN Host 
- Internal Apps, Prototyping 
- No Proxy, No SSL Provisioning 
- Run on ports other than port 80
- Single Server (mostly) 
- Service goes offline during Deploy

## Implementation 

Sysd will be built a tech stack including:

- Elixir          | With common Elixir tooling
- Elixir MixTasks | The CLI for all interaction
- Elixir Releases | Self-contained packaging standard
- SSHex           | Elixir SSH package 
- Systemd         | The management tool on remote servers

```
Sysd - Deploy Elixir releases to bare metal servers

Mix Tasks:
  mix sysd                     This help message
  mix sysd.init                Generate config stubs
  mix sysd.sshcheck            Check SSH connection and permissions
  mix sysd.setup               Setup servers and deploy
  mix sysd.deploy              Deploy app to servers
  mix sysd.versions            List release versions on servers
  mix sysd.rollback [VERSION]  Rollback to a previous version
  mix sysd.remove [VERSION]    Remove old releases
  mix sysd.cleanup [SERVER]    Remove everything from server
```

**sysd.init** 

- create a default config file in config/sysd.yaml 
- create a systemd service file in priv/sysd/<appname>.service

```yaml
servers: 
  - host1 
  - host2 
ssh:
  user: <name> 
```

The service file should be an EEX template.

**sysd.sshcheck**

on all servers:
- test ssh connection 
- make sure the deploy user has sudo access 
- make sure the deploy user can create /opt/sysd 

**sysd.setup** 

for each server: 
- create service file /etc/systemd/services/<appname>.service
- create /opt/sysd 
- deploy (see below)

**sysd.deploy**
- generate a new release `MIX_ENV=prod mix release`

for each server:
- copy the tar file to the remote server /opt/sysd/<appname>/archives/<version>.tar 
- untar the release file into /opt/sysd/<appname>/releases/<version>
- set the symlink /opt/sysd/<appname>/current to point to /opt/sysd/<appname>/releases/<version>
- start or restart the service `sudo systemctl <appname> start`

**sysd.versions** 

for each server: 
- ls /opt/sysd/<appname>/releases 

**sysd.rollback**

get the <version> number

for each server:
- set the symlink /opt/sysd/<appname>/current to point to /opt/sysd/<appname>/releases/<version>
- restart the service `system systemctl <appname> restart`

**sysd.remove** 

get the <version> number
do not remove current version

for each server:
- remove /opt/sysd/<appname>/releases/<version>
- remove /opt/sysd/<appname>/archives/<version>.tar 

**sysd.cleanup**

for <server>:
- remove server from config/sysd.yaml 
- remove service file 
- remove /opt/sysd/<appname>

