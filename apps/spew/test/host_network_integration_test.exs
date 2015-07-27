defmodule SpewHostNetIntegratioNTest do
  use ExUnit.Case

  alias Spew.Network
  alias Spew.Network.Slice
  alias Spew.Host

  test "map host to netslice", ctx do
    hostcluster = "#{ctx[:test]}-hosts"
    netcluster = "#{ctx[:test]}-networks"

    {:ok, hostserver} = Host.Server.start_link name: :"#{ctx[:test]}-host",
                                               init: [cluster: hostcluster]

    network = %Network{name: "#{ctx[:test]}",
                       ranges: ["fe00::f:1/48#59"]}

    {:ok, netserver} = Network.Server.start_link name: :"#{ctx[:test]}-net",
                                                 init: [cluster: netcluster, networks: [network]]

    {:ok, [network]} = Network.networks netcluster

    send hostserver, {:nodeup, node}
    hostname = "#{:net_adm.localhost}"
    netref = network.ref
    hostopts = Dict.put([], Spew.Network.Server, netcluster)

    assert :ok = Host.netjoin "#{:net_adm.localhost}", network.ref, hostopts, hostcluster
    assert {:ok, %Spew.Host{networks: [netref]}} = Host.get "#{:net_adm.localhost}", hostcluster
    assert {:ok, [%Slice{owner: ^hostname}]} = Network.slices network.ref, netcluster

    assert :ok = Host.netleave "#{:net_adm.localhost}", network.ref, hostopts, hostcluster
    assert {:ok, %Spew.Host{networks: []}} = Host.get "#{:net_adm.localhost}", hostcluster
    assert {:ok, []} = Network.slices network.ref, netcluster
  end
end
