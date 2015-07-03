defmodule RunnerSystemdNspawnTest do
  # Test some aspects of running SystemD
  # Note that this is also one of the only places where we test
  # overlay, build and network plugin integration
  use ExUnit.Case

  alias Spew.Instance
  alias Spew.Instance.Server
  alias Spew.Instance.Item
  alias Spew.Runner.SystemdNspawn, as: Runner

  setup_all do
    rootfs = Path.join [__DIR__, "runner", "busyboxroot"]

    unless File.exists? target = Path.join [rootfs, "bin", "busybox"] do
      File.mkdir_p! Path.join([rootfs, "bin"])
      File.cp! System.find_executable("busybox"), target
    end

    {:ok, [rootfs: rootfs]}
  end

  test "basic output", ctx do
    {:ok, server} = Server.start_link name: ctx[:test]
    val = "helo"
    spec = %Item{runner: Runner,
                 runtime: {:chroot, ctx[:rootfs]},
                 name: "#{ctx[:test]}",
                 env: %{"VAR" => val},
                 command: "/bin/busybox sh -c 'echo $VAR'"}

    {:ok, instance} = Instance.run spec, [subscribe: [self]], server

    assert {:stopped, _} = instance.state

    ref = instance.ref
    match = "#{val}\n"
    assert_received {:output, ^ref, ^match}
  end

  test "stop normal", ctx do
    {:ok, server} = Server.start_link name: ctx[:test]
    spec = %Item{runner: Runner,
                 runtime: {:chroot, ctx[:rootfs]},
                 name: "#{ctx[:test]}",
                 command: "/bin/busybox sleep 60"}

    {:ok, instance} = Instance.run spec, [subscribe: [self]], server

    assert {:running, _} = instance.state
    {:ok, instance} = Instance.stop instance.ref, [], server

    assert {:stopping, _} = instance.state
    {:ok, pid} = Runner.pid instance
    monref = Process.monitor pid

    assert_receive {:DOWN, ^monref, :process, _, :normal}
  end

  test "kill instance" do
  end

  test "io loop" do
  end

end
