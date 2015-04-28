defmodule ShellApplianceTest do
  use ExUnit.Case

  alias Spew.Appliance
  alias Spew.Appliance.Manager
  alias Spew.Appliance.Config

  setup do
    Config.unload :all
    Config.load "test/config/shell.config"
  end

  test "shell runner" do
    # check that shell appliance exists and is executable
    {:error, {:missing_runtime, "/non-executable"}} = Appliance.run "non-executable"

    {:error, {:missing_runtime, "/non-executable"}} = Appliance.run "non-executable"
    {:ok, appref} = Appliance.run "echo client"
    {:ok, {appref, appstate}} = Manager.get(appref)
    pid = appstate[:runstate][:pid]

    assert {:ok, {_, :alive}} = Appliance.status appref
    assert_receive {:stdout, _, "hello\n"}, 100
    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 1000
    assert {:ok, {_, :stopped}} = Appliance.status appref
    :ok = Appliance.delete appref

    # Ensure clean exists gets purged from manager
    assert {:error, :not_found} = Manager.get appref

    {:ok, appref} = Appliance.run "slow echo client"
    {:ok, {^appref, appstate}} = Manager.get(appref)
    pid = appstate[:runstate][:pid]

    assert :ok = Appliance.stop appref
    assert_receive {:DOWN, _ref, :process, ^pid, :normal}, 10000

    # Ensure it's removed from the manager when stop is called
    assert {:error, :not_found} = Manager.get appref
  end
end
