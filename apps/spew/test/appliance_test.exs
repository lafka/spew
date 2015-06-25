defmodule SpewApplianceTest do
  use ExUnit.Case

  alias Spew.Appliance

  alias Spew.Appliance.NoRuntime
  alias Spew.Appliance.ConfigError


  setup do
    Appliance.reset
  end

  test "get by name" do
    {:ok, app} = Appliance.add "get-by-name", nil, %{}, true
    assert {:ok, ^app} = Appliance.get app.name
  end

  test "get by ref" do
    {:ok, app} = Appliance.add "get-by-ref", nil, %{}, true
    assert {:ok, ^app} = Appliance.get app.ref
  end

  test "delete by name" do
    {:ok, app} = Appliance.add "delete-by-name", nil, %{}, true
    :ok = Appliance.delete app.name
    {:error, {:notfound, {:appliance, _}}} = Appliance.get app.name
  end

  test "delete by ref" do
    {:ok, app} = Appliance.add "delete-by-ref", nil, %{}, true
    :ok = Appliance.delete app.ref
    {:error, {:notfound, {:appliance, _}}} = Appliance.get app.ref
  end

  test "list appliances" do
    {:ok, app1} = Appliance.add "list-1", nil, %{}, true
    {:ok, app2} = Appliance.add "list-2", nil, %{}, true
    {:ok, app3} = Appliance.add "list-3", nil, %{}, true
    {:ok, app4} = Appliance.add "list-4", nil, %{}, true

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
    {:error, {:load, _}} = Appliance.loadfiles ["./i-dont-exist"]

    {:error, {:notfound, {:appliance, "void"}}} = Appliance.get "void"
    :ok = Appliance.loadfiles ["./test/appliances/void.exs"]

    {:ok, _void} = Appliance.get "void"
  end

  test "config: unload file" do
    {:error, {:notfound, {:appliance, "void"}}} = Appliance.get "void"
    :ok = Appliance.loadfiles ["./test/appliances/void.exs"]

    {:ok, _void} = Appliance.get "void"
    :ok = Appliance.unloadfiles ["./test/appliances/void.exs"]

    {:error, {:notfound, {:appliance, "void"}}} = Appliance.get "void"

  end

  test "config: refute access to `appliance` and `ref`" do
    assert {:error, {:syntax, _}} = Appliance.loadfiles ["./test/priv/broken-appliance-syntax.exs"]
    assert {:error, %ConfigError{}} = Appliance.loadfiles ["./test/priv/broken-appliance.exs"]
    assert {:error, %ConfigError{}} = Appliance.loadfiles ["./test/priv/broken-appliance-ref.exs"]
  end

  test "find runtime" do
    # Check that when no runtime specified
    {:ok, app} = Appliance.add "no-runtime", nil, %{}, true
    assert nil == app.runtime
    assert nil == app.builds.()

    # Add specific runtimes
    runtimeref = "i'm-a-build"
    {:ok, app} = Appliance.add "concrete-runtime", {:ref, runtimeref}, %{}, true
    assert [runtimeref] == app.builds.()

    runtimerefs = ["so", "many", "builds"]
    {:ok, app} = Appliance.add "concrete-runtimes", {:ref, runtimerefs}, %{}, true
    assert runtimerefs == app.builds.()

    # There is no runtime
    {:ok, app} = Appliance.add "no-find-runtime", {:query, "TARGET == 0"}, %{}, true
    assert [] == app.builds.()

    {:ok, app} = Appliance.add "find-runtime", {:query, "TARGET == 'dummy'"}, %{}, true
    assert [{_ref, _spec} | _] = app.builds.()
  end
end
