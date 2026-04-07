# Relman Design Overview 

Relman is a minimalist tool for deploying Elixir Releases.

## Deploy Tool Comparison 

There are many deploy tools for Elixir Releases: 

- Kamal | Ruby Deploy Tool 
- Xamal | Elixir Deploy Tool
- Cogni | Bash Tool Generators

These tools are great for production deployment in commercial environments, at
the expense of complexity and learning-curve.

Relman Use Case:

- Deploy on LAN Host 
- Internal Apps, Prototyping 
- No Proxy, No SSL Provisioning 
- Run on ports other than port 80
- Single Server (mostly) 
- Service goes offline during Deploy

## Implementation 

Relman will be built a tech stack including:

- Elixir          | With common Elixir tooling
- Elixir MixTasks | The CLI for all interaction
- Elixir Releases | Self-contained packaging standard
- SSHex           | Elixir SSH package 
- Systemd         | The management tool on remote servers

```
Relman - Deploy Elixir releases to bare metal servers

Mix Tasks:
  mix relman                     This help message
  mix relman.init                Generate config stubs
  mix relman.sshcheck            Check SSH connection and permissions
  mix relman.setup               Setup servers and deploy
  mix relman.deploy              Deploy app to servers
  mix relman.versions            List release versions on servers
  mix relman.rollback [VERSION]  Rollback to a previous version
  mix relman.remove [VERSION]    Remove old releases
  mix relman.cleanup [SERVER]    Remove everything from server
```

**relman.init** 

- create a default config file in config/relman.yaml 
- create a systemd service file in priv/relman/<appname>.service

```yaml
servers: 
  - host1 
  - host2 
ssh:
  user: <name> 
```

The service file should be an EEX template.

**relman.sshcheck**

on all servers:
- test ssh connection 
- make sure the deploy user has sudo access 
- make sure the deploy user can create /opt/relman 

**relman.setup** 

for each server: 
- create service file /etc/systemd/services/<appname>.service
- create /opt/relman 
- deploy (see below)

**relman.deploy**
- generate a new release `MIX_ENV=prod mix release`

for each server:
- copy the tar file to the remote server /opt/relman/<appname>/archives/<version>.tar 
- untar the release file into /opt/relman/<appname>/releases/<version>
- set the symlink /opt/relman/<appname>/current to point to /opt/relman/<appname>/releases/<version>
- start or restart the service `sudo systemctl <appname> start`

**relman.versions** 

for each server: 
- ls /opt/relman/<appname>/releases 

**relman.rollback**

get the <version> number

for each server:
- set the symlink /opt/relman/<appname>/current to point to /opt/relman/<appname>/releases/<version>
- restart the service `system systemctl <appname> restart`

**relman.remove** 

get the <version> number
do not remove current version

for each server:
- remove /opt/relman/<appname>/releases/<version>
- remove /opt/relman/<appname>/archives/<version>.tar 

**relman.cleanup**

for <server>:
- remove server from config/relman.yaml 
- remove service file 
- remove /opt/relman/<appname>

