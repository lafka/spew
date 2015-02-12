defmodule SpewApplianceTest do
  use ExUnit.Case

  alias Spew.Appliance


  setup do
    Appliance.reset
  end

  test "get by name" do
    {:ok, app} = Appliance.add "get-by-name", "", %{}, true
    assert {:ok, ^app} = Appliance.get app.name
  end

  test "get by ref" do
    {:ok, app} = Appliance.add "get-by-ref", "", %{}, true
    assert {:ok, ^app} = Appliance.get app.ref
  end

  test "delete by name" do
    {:ok, app} = Appliance.add "delete-by-name", "", %{}, true
    :ok = Appliance.delete app.name
    {:error, {:notfound, {:appliance, _}}} = Appliance.get app.name
  end

  test "delete by ref" do
    {:ok, app} = Appliance.add "delete-by-ref", "", %{}, true
    :ok = Appliance.delete app.ref
    {:error, {:notfound, {:appliance, _}}} = Appliance.get app.ref
  end

  test "list appliances" do
    {:ok, app1} = Appliance.add "list-1", "", %{}, true
    {:ok, app2} = Appliance.add "list-2", "", %{}, true
    {:ok, app3} = Appliance.add "list-3", "", %{}, true
    {:ok, app4} = Appliance.add "list-4", "", %{}, true

    {:ok, apps} = Appliance.list
    assert Enum.sort([app1, app2, app3, app4]) == Enum.sort(apps)
  end

  test "(re)load files from disk" do
    :ok = Appliance.reload Appliance.Server.appliancefiles
    {:ok, void} = Appliance.get "void"

    assert "void" == void.name
    assert Spew.Runner.Void == void.instance.runner
  end

  test "config: load file" do
    {:error, {:notfound, {:appliance, "void"}}} = Appliance.get "void"
    :ok = Appliance.loadfiles ["./test/appliances/void.exs"]

    {:ok, void} = Appliance.get "void"

    # check non existing file
  end

  test "config: unload file" do
    {:error, {:notfound, {:appliance, "void"}}} = Appliance.get "void"
    :ok = Appliance.loadfiles ["./test/appliances/void.exs"]

    {:ok, void} = Appliance.get "void"
    :ok = Appliance.unloadfiles ["./test/appliances/void.exs"]

    {:error, {:notfound, {:appliance, "void"}}} = Appliance.get "void"

    # error on non-loaded file
  end

  test "config: refute access to appliance opt" do
  end

  test "find runtime" do
  end
end
