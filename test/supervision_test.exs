defmodule SupervisionTest do
  use ExUnit.Case, async: false

  alias Spew.Appliance.Manager
  alias Spew.Appliance.Config

  setup do
    :ok = Config.unload :all
    :ok = Config.load "test/config/supervison.config"
  end

  test "restart on non-zero" do
    {:ok, appref} = Spew.Appliance.run "read-nonzero", %{restart: [:crash]}
    {:ok, {appref, appcfg}} = Manager.get appref

    :exec.send(appcfg[:runstate][:pid], "\r\n")

    {:ok, {:crash, {:exit_status, 256}}} = Manager.await appref, &match?({:crash, _}, &1), 1000
    {:ok, {:start, 1}} = Manager.await appref, &match?({:start, _}, &1), 1000
  end

  test "always restart" do
  end
end
