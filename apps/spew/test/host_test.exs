defmodule SpewHostTest do
  use ExUnit.Case

  alias Spew.Host

  test "auto create host on startup" do
    hostnode = node
    assert {:ok, [%Host{node: ^hostnode}]} = Host.query
  end

  test "node(up,down)", ctx do
    {:ok, server} = Host.Server.start_link name: ctx[:test], init: [cluster: "#{ctx[:test]}"]

    assert {:ok, []} = Host.query nil, server

    {:ok, %Host{node: nil} = host} = Host.add "node.local", server
    assert {:ok, [^host]} = Host.query nil, server


    send server, {:nodeup, :"test@node.local"}
    assert {:ok, [%Spew.Host{node: :"test@node.local", up?: true}]} = Host.query nil, server

    send server, {:nodedown, :"test@node.local"}
    assert {:ok, [%Spew.Host{node: :"test@node.local", up?: false}]} = Host.query nil, server
  end

  test "cluster test", ctx do
    cluster = "#{ctx[:test]}"
    {:ok, server1} = Host.Server.start_link name: :"#{ctx[:test]}-1", init: [cluster: cluster]
    {:ok, server2} = Host.Server.start_link name: :"#{ctx[:test]}-2", init: [cluster: cluster]

    {:ok, %Host{node: nil} = host} = Host.add "node.local", cluster

    assert Host.query(nil, server1) == Host.query(nil, server2)
    :ok = Host.remove "node.local", cluster
  end
end
