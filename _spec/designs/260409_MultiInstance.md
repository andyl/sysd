# Multi-Instance Services - Preliminary Design 

## Overview 

We have discovered that for a given application with a given release tarball,
we may wish to deploy different service instances across various hosts, 
and even different service instances on a single host.

The configuration mechanism for these service variations will be:

1) the systemd service file name & description - the instance NAME
2) environment variables within the service file - the instance ENVIRONMENT VARIABLES

Besides these elements, the start and stop commands for all sysd services will be the same:

```
ExecStart=/opt/sysd/<myapp>/current/bin/<myapp> start
ExecStop=/opt/sysd/<myapp>/current/bin/<myapp> stop
```

Essentially - we require a mechanism to inject templated service files into the target host, one for each instance.

People say: "the production instance", "start the staging instance", "all instances of myapp".

Another way of describing the hierarchy:
- an application can have (reside on) one or more servers 
- a server can have many application instances, each with it's own unique configuration (done with environment variables)

## Configuration Example 

Config files may live at the project level (in config/sysd.yml) or system-wide (in ~/.config/sysd/config.yml), or an independent directory defined by SYSD_CONFIG_DIR.

Order of precedence: SYSD_CONFIG_DIR > ~/.config/sysd/config.yml > config/sysd.yml 

Example config for project "docpub" in config/sysd.yml:

```yml
servers: 
  - host1: 
    - instance_name: docpub1 
      environment_variables: 
        - PATH=~/util/org 
        - PORT=4067 
        - HOST=0.0.0.0 
        - TITLE=MyDocs 
    - instance_name: docpub2
      environment_variables: 
        - PATH=~/docs/repo1
        - PORT=4064
        - TITLE="Joe's Docs"
  - host2: 
    ...
```

Example config for in ~/.config/sysd/config.yml:

```yml
apps:
  - docpub: 
    tarfile_source: github:joex/docpub
    servers: 
      - host1: 
        - instance_name: docpub1
          environment_variables: 
            - PATH=~/util/org 
            - PORT=4067 
            - HOST=0.0.0.0 
            - TITLE=MyDocs 
        - instance_name: docpub2
          environment_variables: 
            - PATH=~/docs/repo1
            - PORT=4064
            - TITLE="Joe's Docs"
      - host2: 
        ...

```

## Host Artifacts 

on host1:
```
/opt/sysd/docpub/releases/...

/etc/systemd/system/sysd_docpub1.service
/etc/systemd/system/sysd_docpub2.service
``` 

/etc/systemd/system/sysd_docpub1.service 
```
[Unit]
Description=docpub1
After=network.target

[Service]
Type=simple
User=aleak
Environment=PHX_SERVER=true
Environment=PATH=~/util/org
Environment=PORT=4067 
Environment=HOST=0.0.0.0 
Environment=TITLE=MyDocs 
Environment=PHX_SERVER=true
ExecStart=/opt/sysd/docpub/current/bin/docpub start
ExecStop=/opt/sysd/docpub/current/bin/docpub stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

/etc/systemd/system/sysd_docpub2.service 
```
[Unit]
Description=docpub2
After=network.target

[Service]
Type=simple
User=aleak
Environment=PHX_SERVER=true
Environment=PATH=~/docs/repo1
Environment=PORT=4064
Environment=TITLE="Joe's Docs"
ExecStart=/opt/sysd/docpub/current/bin/docpub start
ExecStop=/opt/sysd/docpub/current/bin/docpub stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

NOTE: service files on /etc/systemd/system/sysd_*.service are prefixed with
'sysd_' in order to track which files are managed by sysd.  This will be
especially useful to help recovery (maybe with a "reset" command) if somehow
the server and config files become mis-aligned.

## Template Storage 

project-specific location: priv/sysd/templates/application.service

system-wide location: ~/.config/sysd/templates/application1.service
                      ~/.config/sysd/templates/application2.service
