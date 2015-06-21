# Spew

**THIS IS PRE-ALPHA SOFTWARE, WE DON'T EVEN RUN IT FOR TESTING**

Spew is an application for zero-configuration systems. It takes your
builds (usually a tarball), does some magic and runs it directly or by
amending it with some template options.

There are some reasons why this tool is being developed:

1) Software like Docker, libvirt, etc are good at running applications.
   They are not good at managing all the other aspects of running
   applications (and in docker's case doing non-default configs for
   the container). We are left with using a pile of other software to
   handle supervision, network config, service discovery, upgrades etc.

2) Throughout the development cycle there's a lot of pain getting
   larger systems up and running. Developers might need to setup their
   own complete environment include multiple machines, the sysadmins
   need to keep multiple separate environments for
   test/staging/production where each environment will be slightly
   different. Complexity arises.

There are off course tools like Puppet, Ansible, Vagrant etc to handle
my issues but I have yet to find a fully integrated solution that
lets me run 'spew start' in any environment (with the only difference
of each env being that one will have 8 Riak servers instead of 3).

**Note:** due to the dependency of `overlayfs` a fairly new kernel
(>= 3.18) is required. There is no problem of adding support for
`aufs` or `unionfs` but I don't use it so it's up to you. Hell, you
could even just copy the files manually.


**Note 2:** Spew is required to run as root and spew is using the
Erlang vm. Erlang expects you to be a on a fully trusted network.
In essence, anyone on your network can with minimal effort get root
access to your box. This is being worked on by using TLS communication
between the Erlang nodes but it will not be fixed for a very long
time.

**Note 3:** This software is heavily under development, but I do like
inputs. Give me a ping if you have questions, comments or something.

## Features

 - Support for running different types of virtualization (only plain shell and linux-namespaces for now)
 - Run existing application within spew (ie. any traditional linux daemon)
 - Signed builds (yay for GPG)
 - Composable appliances (templates)
 - Distributed out of the box

# Details

## Builds

Builds are tarballs. They contain the entire filesystem that you are
running. This can include your Go application, a minimal busybox
system or a full linux distribution. Builds are stupid and know
nothing about how they are ran except that by default we call `/run.sh`

## Appliances

An appliance is a template on how to run things. An appliance can use
a build to provide the runtime system or it can be a shell command
using a chroot on the box itself.

## Instances

An instance is your virtual host, it can be transient (meaning
everything is defined in the instance config) or it can inherit from a
`appliance`.

Instances can currently be ran using:
 - `systemd-nspawn` using overlayfs for the rootfs and namespaces for isolation
 - `shell` a shell script running on the host directly
 - `void` it does not actually run anything but lets you add
   externally ran applications into the mix (ie. you want to monitor
   some external pid or have static configuration in there)

## Hosts

A host is something running the spew app. Each host will have it's own
network configuration independent of Spew and we will try to use
information from the host when filling  in stuff like network config.

## Spewpanel

The online dashboard running on each host. This will easily let you inspect
the system and do some common actions like restart an app, view a log
file or something. Functionality have yet to be defined
