defmodule LogTest do
  use ExUnit.Case, async: false

  alias Spew.Appliance
  alias Spew.Appliance.Manager

  test "write log" do
    {:ok, appref} = Appliance.run nil, %{
      type: :shell,
      appliance: ["/bin/bash", []],
      runneropts: ["/bin/bash  -c 'for f in 1 2 3 4 5 6; do echo $f; sleep 0.1; done'"]
    }

    assert {:ok, :stop} = Manager.await appref, &match?(:stop, &1), 2000
  end
end
