Spew
=======

**THIS IS AT BEST PRE-ALPHA, YOU WILL REGRET USING IT - do stay tuned for updates though :)**

Docker is nice, there's alot of tooling around but nothing seems to
work nicely together unless you build it into your docker image. Even
managing containers without running a full blown PaaS seems daunting.

The aim of Spew is to dock applications, meaning:
 - run applications (most likely a container) - called appliance
 - manage container upgrades
 - provide a mechanism to easily hook into create,crash,remove actions

The scope is not limited to docker, it can be a LXC container, shell command
or something radically different.


## API

There's the appliance API which runners must comply to:

```
# Create an appliance 
Spew.Appliance.create <appliance> :: Appliance,
	<app-opts> :: %{
		name: String,
		appliance: appliancePreCond :: term
		type: :docker | :shell,
		hooks: %{
			<hook>: [action]
		},
		depends: [appliancePreCond :: term, ..],
		runneropts: <opts> :: Term,
		restart: true | false | restartStrategy
	} -> ApplianceRef

# Remove a appliance
Spew.Appliance.remove ApplianceRef || name

# Run a appliance, if app-opts.name is given it must be unique
Spew.Appliance.run <appliance>, <app-opts> # {@see create}
```

## Configuration

Configuration is split into two parts:
- Instance config
- Appliance config

The instance config provides default values for the instance itself
and is applied on every boot. The Appliance config is only applied
the first time the instance starts.

The configuration file takes is a tuple list: `{ApplianceSpec, ItemOpts}`
Where ApplianceSpec is a string containing the appliance name with a
possible suffix "#" + opts which is a comma separated list with
additional parameters (for instance `vsn:~>2.0`). These options are
free-form and up to the indivudual appliance handler to process and
use.

The ItemOpts is according to `Spew.Appliance.Config.Item`.

When this is processed two additional keys will be added to ItemOpts:
 - `ref` - the reference of that particular config
 - `file` - the file this was loaded from, may be nil in case it was
   added at runtime

### Default values

The special key "\_" can be used to indicate default values for that
particular config file

### State

The state of the process manager is simple:
 - there's a list of all monitor refs and what appliances they are
   connected to. This is to allow clearing up stuff once they die/exit
 - The appliance list. This keeps the `ref -> app-state` map.
   App-state is here things given by the appliance runner (ie.
	`Spew.Appliances.Shell` or `Spew.Appliances.Docker`).

## @todo - Clustering

A cluster of Spew instance can be established. They will then share the
registry of running hosts allowing a low-level of orchestration.
The clustering will rely on Erlangs clustering capabilities and the
`Spew.Appliance` API will act on the cluster as a whole (ie. a host
can spawn appliances on other hosts, events will be distributed and
the state of all the Spew instances will be will available on all
nodes through gproc.



## @todo

 - The config for all appliances must be versioned to allow restarting or recreating an identical instance.
 - restart strategies
	- add max_restarts
 - add support for hooks
 - add support for dependencies
 - patch appref's in await when a upgrade is done
 - Add CLI
  - `spew-cli start <ref-or-name || --all>`
  - `spew-cli stop [-k|--kill] <ref-or-name, .. || --all>`
  - `spew-cli status [ref-or-name, ..]`
  - `spew-cli attach <ref-or-name>`
  - `spew-cli logs [-f] [-t n] <ref-or-name>`
 - Add release generation!!!
 - Add systemd service file
 - Add upstart service file
 - Add init.d script
 - Generate deb/rpm package?
