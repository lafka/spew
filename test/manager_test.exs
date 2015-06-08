defmodule ManagerTest do
  use ExUnit.Case, async: false

  alias Spew.Appliance.Manager

  test "server commands" do
    {:ok, appref} = Manager.run [[], []], [a: 1]
    assert {:ok, {^appref, %{runstate: [a: 1]}}} = Manager.get appref

    assert :ok = Manager.set appref, :runstate, [a: 2]
    assert {:ok, {appref, %{runstate: [a: 2]}}} = Manager.get appref

    assert :ok = Manager.delete appref
    assert {:error, :not_found} = Manager.get appref
  end

  test "await" do
    p = :global.whereis_name Manager
    Process.send_after p, {:event, "a", {:a, 1}}, 100
    assert {:ok, {:a, 1}} = Manager.await "a", &match?({:a, _}, &1), 1000
    send p, {:event, "a", {:a, 1}}
    assert {:error, :timeout} = Manager.await "a", &match?({:a, _}, &1), 1000
  end
end
