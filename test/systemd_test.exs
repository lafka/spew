defmodule SystemdTest do
  use ExUnit.Case

  alias Spew.Appliance
  alias Spew.Appliance.Config
  alias Spew.Appliance.Manager

  defp flush() do
    receive do
      _ -> flush
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

  test "status" do
    {:ok, cfgref} = Appliance.create "systemd", %Config.Item{
      name: "systemd",
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh -c 'echo systemd-container; sleep 1'"],
        root: {:busybox, "./test/chroot"}
      ]
    }

    {:ok, appref} = Appliance.run "systemd"

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
    nil
  end

  test "archive chroot" do
  end

  test "image chroot" do
  end

  test "tmpfs chroot" do
  end

  test "bridge network" do
  end

  test "host iface network" do
  end

  test "vlan network" do
  end

  test "macvlan network" do
  end

  test "expose ports" do
  end

  test "mounts" do
  end
end
