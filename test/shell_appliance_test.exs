defmodule ShellApplianceTest do
  use ExUnit.Case

  require Logger

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
    {:ok, appref} = Appliance.run "echo client", %{}, [subscribe: [:log]]
    {:ok, {appref, _appstate}} = Manager.get(appref)

    assert {:ok, {_, :alive}} = Appliance.status appref
    assert_receive {:log, ^appref, {:stdout, "hello\n"}}, 1000
    {:ok, :stop} = Manager.await appref, &match?(:stop, &1), 5000

    assert {:ok, {_, :stopped}} = Appliance.status appref
    :ok = Appliance.delete appref

    # Ensure clean exists gets purged from manager
    assert {:error, :not_found} = Manager.get appref

    {:ok, appref} = Appliance.run "slow echo client"
    {:ok, {^appref, appstate}} = Manager.get(appref)
    pid = appstate[:runstate][:pid]

    assert Process.alive? pid

    Process.flag :trap_exit, true
    pid = spawn fn ->
      :timer.sleep 10 # wait for manager to register event handler
      :ok = Appliance.stop appref, keep?: false
    end

    {:ok, :stop} = Manager.await appref, &match?(:stop, &1), 5000

    # Ensure it's removed from the manager when stop is called
    assert {:error, :not_found} = Manager.get appref
  end
end
