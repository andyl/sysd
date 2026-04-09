# RelDep Design Overview 

RelDep is a minimalist tool for deploying Elixir Releases.

## Deploy Tool Comparison 

There are many deploy tools for Elixir Releases: 

- Kamal | Ruby Deploy Tool 
- Xamal | Elixir Deploy Tool
- Cogni | Bash Tool Generators

These tools are great for production deployment in commercial environments, at
the expense of complexity and learning-curve.

RelDep Use Case:

- Deploy on LAN Host 
- Internal Apps, Prototyping 
- No Proxy, No SSL Provisioning 
- Run on ports other than port 80
- Single Server (mostly) 
- Service goes offline during Deploy

## Implementation 

RelDep will be built a tech stack including:

- Elixir          | With common Elixir tooling
- Elixir MixTasks | The CLI for all interaction
- Elixir Releases | Self-contained packaging standard
- SSHex           | Elixir SSH package 
- Systemd         | The management tool on remote servers

```
RelDep - Deploy Elixir releases to bare metal servers

Mix Tasks:
  mix reldep                     This help message
  mix reldep.init                Generate config stubs
  mix reldep.sshcheck            Check SSH connection and permissions
  mix reldep.setup               Setup servers and deploy
  mix reldep.deploy              Deploy app to servers
  mix reldep.versions            List release versions on servers
  mix reldep.rollback [VERSION]  Rollback to a previous version
  mix reldep.remove [VERSION]    Remove old releases
  mix reldep.cleanup [SERVER]    Remove everything from server
```

**reldep.init** 

- create a default config file in config/reldep.yaml 
- create a systemd service file in priv/reldep/<appname>.service

```yaml
servers: 
  - host1 
  - host2 
ssh:
  user: <name> 
```

The service file should be an EEX template.

**reldep.sshcheck**

on all servers:
- test ssh connection 
- make sure the deploy user has sudo access 
- make sure the deploy user can create /opt/reldep 

**reldep.setup** 

for each server: 
- create service file /etc/systemd/services/<appname>.service
- create /opt/reldep 
- deploy (see below)

**reldep.deploy**
- generate a new release `MIX_ENV=prod mix release`

for each server:
- copy the tar file to the remote server /opt/reldep/<appname>/archives/<version>.tar 
- untar the release file into /opt/reldep/<appname>/releases/<version>
- set the symlink /opt/reldep/<appname>/current to point to /opt/reldep/<appname>/releases/<version>
- start or restart the service `sudo systemctl <appname> start`

**reldep.versions** 

for each server: 
- ls /opt/reldep/<appname>/releases 

**reldep.rollback**

get the <version> number

for each server:
- set the symlink /opt/reldep/<appname>/current to point to /opt/reldep/<appname>/releases/<version>
- restart the service `system systemctl <appname> restart`

**reldep.remove** 

get the <version> number
do not remove current version

for each server:
- remove /opt/reldep/<appname>/releases/<version>
- remove /opt/reldep/<appname>/archives/<version>.tar 

**reldep.cleanup**

for <server>:
- remove server from config/reldep.yaml 
- remove service file 
- remove /opt/reldep/<appname>

