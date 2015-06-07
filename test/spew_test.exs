defmodule SpewTest do
  use ExUnit.Case

  alias Spew.Appliance
  alias Spew.Appliance.Config
  alias Spew.Appliance.Manager

  setup do
    Config.unload :all
    {:ok, status} = Appliance.status
    Dict.keys(status) |> Enum.each fn(appref) -> Manager.delete appref end
  end

  test "only existing appliances can run" do
    # test name is suggestive, you can run non-existing appliances
    # BUT they must be explicitly set as transient
    {:error, {:not_found, "this-stuff"}} = Appliance.run "this-stuff", %Config.Item{
        type: :shell,
        appliance: ["/bin/ls", []],
        runneropts: ["ls"],
      }
  end

  test "run transient appliance" do
    cfg = %{
      name: "void",
      type: :void
    }

    {:ok, appref}               = Appliance.run nil, cfg
    assert {:ok, {_, :alive}}   = Appliance.status appref
    :ok                         = Appliance.stop appref, keep?: true
    assert {:ok, {_, :stopped}} = Appliance.status appref
  end

  test "status" do
    cfg = %{
      name: "void",
      type: :void
    }

    {:ok, appref1} = Appliance.run nil, cfg
    {:ok, appref2} = Appliance.run nil, cfg
    {:ok, appref3} = Appliance.run nil, cfg
    {:ok, appref4} = Appliance.run nil, cfg

    {:ok, statuses} = Appliance.status
    for {k, {_, status}} <- statuses do
      assert :alive === status, "appref #{k} does not match :state := :alive"
    end


    :ok = Appliance.stop appref2, keep?: true
    :ok = Appliance.stop appref4, keep?: true

    {:ok, statuses} = Appliance.status

    assert {_, :alive} = statuses[appref1]
    assert {_, :stopped} = statuses[appref2]
    assert {_, :alive} = statuses[appref3]
    assert {_, :stopped} = statuses[appref4]
  end
end
