defmodule SpewApplianceTest do
  use ExUnit.Case

  alias Spew.Appliance


  setup do
    Appliance.reset
  end

  test "get by name" do
    {:ok, app} = Appliance.add "get-by-name", {:void, nil}, %{}, true
    assert {:ok, ^app} = Appliance.get app.name
  end

  test "get by ref" do
    {:ok, app} = Appliance.add "get-by-ref", {:void, nil}, %{}, true
    assert {:ok, ^app} = Appliance.get app.ref
  end

  test "delete by name" do
    {:ok, app} = Appliance.add "delete-by-name", {:void, nil}, %{}, true
    :ok = Appliance.delete app.name
    {:error, {:notfound, {:appliance, _}}} = Appliance.get app.name
  end

  test "delete by ref" do
    {:ok, app} = Appliance.add "delete-by-ref", {:void, nil}, %{}, true
    :ok = Appliance.delete app.ref
    {:error, {:notfound, {:appliance, _}}} = Appliance.get app.ref
  end

  test "list appliances" do
    {:ok, app1} = Appliance.add "list-1", {:void, nil}, %{}, true
    {:ok, app2} = Appliance.add "list-2", {:void, nil}, %{}, true
    {:ok, app3} = Appliance.add "list-3", {:void, nil}, %{}, true
    {:ok, app4} = Appliance.add "list-4", {:void, nil}, %{}, true

    {:ok, apps} = Appliance.list
    assert Enum.sort([app1, app2, app3, app4]) == Enum.sort(apps)
  end

  test "(re)load files from disk" do
    :ok = Appliance.reload
    {:ok, void} = Appliance.get "void"

    assert "void" == void.name
    assert Spew.Runner.Void == void.instance.runner
  end
end
