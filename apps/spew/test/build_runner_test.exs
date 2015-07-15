defmodule SpewBuildRunnerTest do

  alias Spew.Instance
  alias Spew.Instance.Item
  alias Spew.Instance.Server, as: InstanceServer

  alias Spew.Build
  alias Spew.Build.Server, as: BuildServer

  use ExUnit.Case

  # - Build should be packed out, sync style
  # - Running two instances of a build should be isolate
  # - stopping will unmount everything, but keep build unpacked
  # - deleting a build should NOT delete the builds files

  test "build integration", ctx do
    {:ok, instserver} = InstanceServer.start_link name: :"#{ctx[:text]}-instance"
    path = Path.join [__DIR__, "runner"]
    {:ok, buildserver} = BuildServer.start_link name: :"#{ctx[:test]}-build",
                                                init: [
                                                  pattern: "../runner",
                                                  searchpath: [path],
                                                  notify_reload?: true
                                                ]

    {:ok, builds} = Build.list buildserver
    [buildref] = Map.keys builds
    spec = %Item{runner: Spew.Runner.LXCExec,
                 runtime: {:build, {:ref, buildref}},
                 command: "/bin/busybox cat /SPEWMETA"}

    {:ok, instance} = Instance.run spec, [{BuildServer, buildserver}, {:subscribe, [self]}], instserver
    {:ok, _instance} = Instance.stop instance.ref, [wait_for_exit: true], instserver

    assert_receive {:output, ref, "TARGET=busybox\n" <> _}

    # overwrite spewmeta
    spec2 = %Item{runner: Spew.Runner.LXCExec,
                  runtime: {:build, {:ref, buildref}},
                  command: "/bin/busybox sh -c 'echo overwrite > /SPEWMETA'"}

    {:ok, instance2} = Instance.run spec2, [{BuildServer, buildserver}, {:subscribe, [self]}], instserver
    {:ok, _instance2} = Instance.stop instance2.ref, [wait_for_exit: true], instserver

    # And check that there's no conflict
    {:ok, instance} = Instance.run spec, [{BuildServer, buildserver}, {:subscribe, [self]}], instserver
    {:ok, _instance} = Instance.stop instance.ref, [wait_for_exit: true], instserver

    ref = instance.ref
    assert_receive {:output, ^ref, "TARGET=busybox\n" <> _}
  end
end
