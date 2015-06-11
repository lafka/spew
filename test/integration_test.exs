defmodule IntegrationTest do
  use ExUnit.Case, async: false

  test "client/server deployment" do
    Spew.Appliance.create "test-server", %{
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh /run.sh"],
        root: {:archive, "./test/integration/server.tar.gz"}
      ]
    }

    Spew.Appliance.create "test-client", %{
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh /run.sh"],
        root: {:archive, "./test/integration/client.tar.gz"}
      ]
    }

    {:ok, clientref} = Spew.Appliance.run "test-client", %{}, [subscribe: [:log]]
    {:ok, serverref} = Spew.Appliance.run "test-server", %{}, [subscribe: [:log]]

    assert "ping" = (receive do {:log, {^serverref, {:stdout, buf}}} -> buf
                     after 5000 -> :timeout end)
    assert "pong" = (receive do {:log, {^clientref, {:stdout, buf}}} -> buf
                     after 5000 -> :timeout end)
  end
end
