defmodule RunnerSystemdNspawnTest do
  use ExUnit.Case

  alias Spew.Instance
  alias Spew.Instance.Server
  alias Spew.Instance.Item
  alias Spew.Runner.SystemdNspawn, as: Runner

  setup do
    id = Spew.Utils.hash :erlang.monotonic_time
    rootfs = Path.join [System.tmp_dir, "spewtest", id]
    bindir = Path.join [rootfs, "bin"]
    busybox = System.find_executable "busybox"

    File.mkdir_p! bindir
    File.cp! busybox, Path.join(bindir, "busybox")

    on_exit fn ->
      # no luck... we need root to delete resolv.conf
      File.rm_rf rootfs
    end

    {:ok, [rootfs: rootfs]}
  end

  test "basic output", ctx do
    {:ok, server} = Server.start_link name: __MODULE__
    val = "helo"
    spec = %Item{runner: Runner,
                 runtime: {:chroot, ctx[:rootfs]},
                 env: %{"VAR" => val},
                 command: "/bin/busybox sh -c 'echo $VAR'"}

    {:ok, instance} = Instance.run spec, [subscribe: [self]], server

    assert {:stopped, _} = instance.state

    ref = instance.ref
    match = "#{val}\n"
    assert_received {:output, ^ref, ^match}
  end

  test "stop normal" do
  end

  test "io loop" do
  end

  test "kill instance" do
  end
end

