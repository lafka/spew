defmodule SystemdTest do
  use ExUnit.Case

  alias Spew.Appliance
  alias Spew.Appliance.Config
  alias Spew.Appliance.Manager

  defp flush(echo? \\ false) do
    receive do
      m ->
        if echo? do
          IO.inspect m
        end
        flush
    after
      0 -> :ok
    end
  end

  setup do
    Config.unload :all
    {:ok, status} = Appliance.status
    Dict.keys(status) |> Enum.each fn(appref) -> Manager.delete appref end

    #if File.exists? __DIR__ <> "/chroot" do
    #  File.rm_rf! __DIR__ <> "/chroot"
    #end
    flush
  end

  defp testname(ctx) do
    "test " <> name = Atom.to_string ctx[:test]
    tokenize name
  end
  defp tokenize(buf), do: String.replace("#{buf}", ~r/[^a-zA-Z0-9-_]/, "-")

  test "status", ctx do
    {:ok, cfgref} = Appliance.create testname(ctx), %Config.Item{
      name: testname(ctx),
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh -c 'echo systemd-container; sleep 1'"],
        root: {:busybox, "./test/chroot"}
      ]
    }

    {:ok, appref} = Appliance.run testname(ctx)

    assert_receive {:stdout, _, "systemd-container\n"}, 1000

    # There will be some weird stderr messages, completely version
    # dependant... flush tehm
    flush
    assert {:ok, {_, :alive}} = Appliance.status appref

    :timer.sleep 1000
    assert_receive {:DOWN, _ref, :process, _pid, :normal}, 1000
    flush

    assert {:ok, {_, :stopped}} = Appliance.status appref
  end

  test "dir chroot" do
    assert nil, "dir chroot test not implemented"
  end

  test "archive chroot" do
    assert nil, "archive chroot test not implemented"
  end

  test "image chroot" do
    assert nil, "image chroot test not implemented"
  end

  test "bridge network", ctx do
    # test for non existing bridge
    {:ok, cfgref} = Appliance.create testname(ctx) <> "a", %Config.Item{
      name: "bridge",
      type: :systemd,
      runneropts: [
        network: [{:bridge, "noonenamestheirbridgethis"}]
      ]
    }

    {:error, {:no_such_iface, _}} = Appliance.run testname(ctx) <> "a"

    # test for non-bridge iface
    {:ok, cfgref} = Appliance.create testname(ctx) <> "b", %Config.Item{
      name: "bridge",
      type: :systemd,
      runneropts: [
        network: [{:bridge, "lo"}]
      ]
    }

    {:error, {:iface_not_bridge, _}} = Appliance.run testname(ctx) <> "b"

    # run with the bridge
    {:ok, cfgref} = Appliance.create testname(ctx), %Config.Item{
      name: "bridge",
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox ip link"],
        root: {:busybox, "./test/chroot"},
        network: [{:bridge, "tm"}]
      ]
    }

    {:ok, appref} = Appliance.run testname(ctx)
    buf = collect 1000
    # check that network is okey, we assume that the host system
    # manages to ensure the bridge availability
    assert Regex.match? ~r/2: host0/, buf
  end

  defp collect(timeout), do: collect("", timeout)
  defp collect(buf, timeout) do
    receive do
      {:stdout, _, data} ->
        collect(buf <> data, timeout)
    after
      timeout ->
        buf
    end
  end

  test "host iface network" do
    assert nil, "host iface net test not implemented"
  end

  test "vlan network" do
    assert nil, "vlan net test not implemented"
  end

  test "macvlan network" do
    assert nil, "macvlan net test not implemented"
  end

  test "expose ports" do
    assert nil, "expose ports test not implemented"
  end

  test "mounts" do
    assert nil, "mount test not implemented"
  end
end
