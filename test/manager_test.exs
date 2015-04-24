defmodule ManagerTest do
  use ExUnit.Case

  alias RTFA.Appliance.Manager

  test "server commands" do
    {:ok, appref} = Manager.run [[], []], [a: 1]
    assert {:ok, {^appref, %{runstate: [a: 1]}}} = Manager.get appref

    assert :ok = Manager.set appref, :runstate, [a: 2]
    assert {:ok, {appref, %{runstate: [a: 2]}}} = Manager.get appref

    assert :ok = Manager.delete appref
    assert {:error, :not_found} = Manager.get appref
  end

  test "await" do
    Process.send_after :procmanager, {:event, "a", {:a, 1}}, 100
    assert {:ok, {:a, 1}} = Manager.await "a", &match?({:a, _}, &1), 1000
    send :procmanager, {:event, "a", {:a, 1}}
    assert {:error, :timeout} = Manager.await "a", &match?({:a, _}, &1), 1000
  end
end
