# Supervision

To ensure your system is running for most of the time you can add
supervision to your appliances. This means that the process will be
restarted when it stops/crashes.

Supervision is defined by a `SupervisionSpec` which is a list of
options specifying how, when and why an appliance should be
restart.

The operation goes as follow, the Appliance.Manager handles events
from the process. The currently supported events are:

 * {:start, start_num :: int()} - started appliance, start_num indicates if it's a restart or not
 * :stop - normal exit
 * {:crash, reason()} - main process stopped with non-zero exit code
 * {:watcher, :timeout} - The external monitor could not detect if the appliance is alive and working before timeout
 * {:watcher, :down} - The external monitor detected that the appliance is down
 * {:dependency, dep(), :stop | :crash | :failed | {:watcher, :timeout|:down}} - a dependency was detected to stop functioning normally
 * :delete - when the appliance is removed

A appliance have the following stats:

 * `:running` - something was stopped normally
 * `:alive` - the process is alive, but may or may not be in a working state
 * `:stopped` - something was stopped normally
 * `:crashed` - something exited with non-zero exit code (meaning error)
 * `:failed` - something have stopped working and and restarting will not help


You can bind the events `:stop`, `:restart`, `:destroy` and `:ignore` to these events
allowing to take actions based on the every changing environment. The
default action for all events are to `:ignore`

## Binding to events

Which events to be bound to can be specified by a option list taking
one of the following parameters:
 * `{:stop, action()}` - take action on `{:exit, :normal}` events
 * `{:crash, action()}` - take action on `{:exit, reason()}` events
 * `{:dependency, dep()|:_, action()}` - take action on a dependency
   failure event
 * `{:watcher, action()}` - take action on any watcher event
 * `{:watcher, :down|:timeout, action()}` - take action on specific watcher event

If `:stop` or `:crash` is given multiple times, then last option will be selected


**Some short hand options:**
 * `:always` - flag that the process should always be restarted (short
   for `crash: :restart, stop: :restart, dependency: :ignore, watcher: :restart`)
 * `:crash` - flag that the process should be restarted only in case of a non-zero exit code
 * `:never` - flag that the process should never be restarted

## Limiting restarts

To ensure that things does not keep being broken forever restarts can
be configured to only trigger a limited amount of time. This is done
by specifying the `{:n, int()}`, `{:n, int(), time()}` and optional
`{:n, int(), time(), 0..inf-1 | int() :: wait()}` which ensures a
waiting period of either int() or somewhere in the range given.

## Watchers & Monitors

There are two types of watchers, the polled and the sync one (hereafter watcher and monitor).
The difference is that the watcher will execute something on a given time
interval while the monitor will be running continuously.

A classic example is that the watcher will do a HTTP request every 5s
while the monitor will hold a open TCP socket (in all practicallity
these are the same thing since TCP sockets will not know when it's
closed until you write, but you get the point...)

Anyway, not everything will support monitors. 


## Future

### Cascading restarts

Sometimes restarting an appliance directly after a dependency failed
may overload the dependency resulting in a infinite crash/restart
loop. There should be some way of saying `{:wait, t()}` before the
appliance restarts. This should encounter for that many other
appliances may do the same and therefor restarts should be throtteled

