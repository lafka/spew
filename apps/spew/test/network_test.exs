defmodule SpewNetworkTest do
  use ExUnit.Case

  alias Spew.Network
  alias Spew.Network.Server
  alias Spew.Network.Slice

  alias Spew.Utils.Net.Iface
  alias Spew.Utils.Net.InetAddress


  test "network -> create, get, list, delete", ctx do
    {:ok, server} = Server.start_link name: :"#{ctx[:test]}"

    {:ok, network} = Network.create %Network{name: "create-get-delete"}, server
    netref = network.ref
    assert {:error, {:conflict, netref}} = Network.create %Network{name: "create-get-delete"}, server
    assert {:ok, network} == Network.get network.ref, server

    assert {:ok, [network]} == Network.networks server

    assert :ok == Network.delete network.ref, server
    assert {:error, {:notfound, netref}} == Network.get network.ref, server
    assert {:error, {:notfound, netref}} == Network.delete network.ref, server
  end


  test "auto-add networks", ctx do
    initopts = [networks: [%Network{name: "auto-add"}], cluster: "#{ctx[:test]}"]
    {:ok, server} = Server.start_link name: :"#{ctx[:test]}", init: initopts

    assert {:ok, [%Network{name: "auto-add"}]} = Network.networks server
  end



  test "slice delegation (delegate, slices, slice, undelegate)", ctx do
    name = "slice-delegation"
    network = %Network{name: name,
                       ranges: ["fe00::a:1/48#59"]}


    {:ok, server} = Server.start name: ctx[:test], init: [networks: [network], cluster: "#{ctx[:test]}"]
    {:ok, [network]} = Network.networks server

    {:ok, slice} = Network.delegate network.ref, [owner: "slice"], server
    sliceref = slice.ref
    assert {:error, {:conflict, {:slices, [sliceref]}, "net-" <> _}} =Network.delegate network.ref, [owner: "slice"], server

    assert {:ok, slice} == Network.slice slice.ref, server

    assert {:ok, [slice]} == Network.slices network.ref, server
    assert {:ok, %Slice{active: false}} = Network.undelegate slice.ref, server
    assert {:error, {:notfound, sliceref}} == Network.slice slice.ref, server
  end

  test "inet allocatation (allocate, deallocate, allocation, allocations)", ctx do
    name = "ip-allocation"
    network = %Network{name: name,
                       ranges: ["fe00::b:1/48#59"]}

    {:ok, server} = Server.start name: ctx[:test], init: [networks: [network], cluster: "#{ctx[:test]}"]
    {:ok, [network]} = Network.networks server
    {:ok, slice} = Network.delegate network.ref, [owner: "slice"], server

    {:ok, alloc1} = Network.allocate slice.ref, "addr-1", server
    {:ok, alloc2} = Network.allocate slice.ref, "addr-2", server

    assert {:error, {:conflict, {:allocations, [alloc1.ref]}, slice.ref}} == Network.allocate slice.ref, "addr-1", server

    assert {:ok, alloc1} == Network.allocation alloc1.ref, server
    assert {:ok, alloc2} == Network.allocation alloc2.ref, server

    assert {:ok, Enum.sort([alloc1, alloc2])} == Network.allocations network.ref, server
    assert {:ok, Enum.sort([alloc1, alloc2])} == Network.allocations slice.ref, server

    assert {:ok, %{alloc1 | state: :inactive}} == Network.deallocate alloc1.ref, server

    assert {:ok, [alloc2]} == Network.allocations network.ref, server
    assert {:ok, [alloc2]} == Network.allocations slice.ref, server
  end

  test "network over-delagation", ctx do
    # what happens when there are no more slices left in network?
    # we have the range 172.16.0.2 to .6 (.1 is the bridge, .7 broadcast)
    # We then allocate delegate 172.16.0.2 to one slice and 172.16.0.4
    # to a different one
    name = "network-over-delegation"
    range = "fe00::c:1/126"
    network = %Network{name: name,
                       ranges: ["#{range}#127", "fe00::d:1/48#59"]}

    {:ok, server} = Server.start_link name: ctx[:test], init: [networks: [network], cluster: "#{ctx[:test]}"]
    {:ok, [network]} = Network.networks server

    {:ok, _slice1} = Network.delegate network.ref, [owner: "slice-1"], server
    {:ok, _slice2} = Network.delegate network.ref, [owner: "slice-2"], server
    assert {:error, {:exhausted, [range], network.ref}} == Network.delegate network.ref, [owner: "slice-3"], server
  end


  test "slice over-allocation", ctx do
    # what happens when there are no more space to allocate in a slice
    name = "slice-over-allocation"
    network = %Network{name: name,
                       ranges: ["fe00::e:1/125#126"]}

    {:ok, server} = Server.start_link name: ctx[:test], init: [networks: [network], cluster: "#{ctx[:test]}"]
    {:ok, [network]} = Network.networks server
    {:ok, slice} = Network.delegate network.ref, [owner: "slice-1"], server
    {ip, mask} = hd slice.ranges
    range = InetAddress.to_string(ip) <> "/#{mask}"

    {:ok, _alloc} = Network.allocate slice.ref, "addr-1", server
    {:ok, _alloc} = Network.allocate slice.ref, "addr-2", server
    assert {:error, {:exhausted, [range], slice.ref}} == Network.allocate slice.ref, "addr-3", server
  end

  test "ip4 allocation", ctx do
    # what happens when there are no more slices left in network?
    # we have the range 172.16.0.2 to .6 (.1 is the bridge, .7 broadcast)
    # We then allocate delegate 172.16.0.2 to one slice and 172.16.0.4
    # to a different one
    name = "ip4 allocation"
    range = "172.20.0.0/29"
    network = %Network{name: name,
                       ranges: ["#{range}#30", "172.20.1.0/24#27"]}

    {:ok, server} = Server.start_link name: ctx[:test], init: [networks: [network], cluster: "#{ctx[:test]}"]
    {:ok, [network]} = Network.networks server
    {:ok, slice} = Network.delegate network.ref, [owner: "slice-1"], server
    {ip, mask} = hd slice.ranges
    range = InetAddress.to_string(ip) <> "/#{mask}"

    {:ok, _alloc} = Network.allocate slice.ref, "addr-1", server
    {:ok, _alloc} = Network.allocate slice.ref, "addr-2", server
    assert {:error, {:exhausted, [range], slice.ref}} == Network.allocate slice.ref, "addr-3", server

  end
  test "auto-(create,delete) bridge", ctx do
    network = %Network{name: "#{ctx[:test]}",
                       ranges: ["fe00::f:1/48#59"]}


    {:ok, server} = Server.start_link name: ctx[:test], init: [networks: [network], cluster: "#{ctx[:test]}"]

    {:ok, [%Network{ref: "net-" <> iface} = network]} = Network.networks server

    {:ok, slice} = Network.delegate network.ref, [owner: "slice"], server
    [{ip, mask}] = slice.ranges
    sliceiface = %{addr: ip, netmask: mask, type: :inet6}

    # * create a bridge on allocation
    {:ok, alloc} = Network.allocate slice.ref, "addr-1", server
    assert {:ok, %Iface{addrs: %{"fe00::ade0:0:0:f:1" => ^sliceiface}}} = Iface.stats iface

    # * on removal of all allocation, the address is removed
    {:ok, _} = Network.deallocate alloc.ref, server
    {:ok, %Iface{addrs: addrs}} = Iface.stats iface
    assert %{} == addrs

    # * on slice undelegation with no allocations the bridge is removed
    {:ok, _} = Network.undelegate slice.ref, server
    assert {:error, {:notfound, {:iface, ^iface}}} = Iface.stats iface

    # * on slice undelegation with active allocations the bridge is # kept
    {:ok, slice} = Network.delegate network.ref, [owner: "slice", iface: iface], server
    {:ok, alloc} = Network.allocate slice.ref, "addr-1", server
    assert {:ok, %Iface{addrs: %{"fe00::ade0:0:0:f:1" => ^sliceiface}}} = Iface.stats iface

    {:ok, _} = Network.undelegate slice.ref, server
    assert {:ok, %Iface{addrs: %{"fe00::ade0:0:0:f:1" => ^sliceiface}}} = Iface.stats iface

    # -> until last allocation is deleted when the bridge is removed
    {:ok, _} = Network.deallocate alloc.ref, server
    assert {:error, {:notfound, {:iface, ^iface}}} = Iface.stats iface
  end


  test "cluster test", ctx do
    network = %Network{name: "#{ctx[:test]}",
                       ranges: ["fe00::f:1/48#59"]}


    cluster = "#{ctx[:test]}"
    {:ok, server1} = Server.start name: :"#{ctx[:test]}-1", init: [cluster: cluster, networks: [network]]
    {:ok, server2} = Server.start name: :"#{ctx[:test]}-2", init: [cluster: cluster]

    assert Network.networks(server1) === Network.networks(server2)
    {:ok, [network]} = Network.networks cluster

    {:ok, slice} = Network.delegate network.ref, [owner: "slice"], cluster
    :timer.sleep 500
    assert Network.networks(server1) === Network.networks(server2)

    {:ok, alloc1} = Network.allocate slice.ref, "addr-1", server1
    {:ok, alloc2} = Network.allocate slice.ref, "addr-2", server2

    assert Network.networks(server1) === Network.networks(server2)

    assert {:error, {:conflict, {:allocations, [alloc1.ref]}, slice.ref}} == Network.allocate slice.ref, "addr-1", cluster

    assert {:ok, alloc1} == Network.allocation alloc1.ref,cluster
    assert {:ok, alloc2} == Network.allocation alloc2.ref, cluster

    assert {:ok, Enum.sort([alloc1, alloc2])} == Network.allocations network.ref, cluster
    assert {:ok, Enum.sort([alloc1, alloc2])} == Network.allocations slice.ref, cluster

    assert {:ok, %{alloc1 | state: :inactive}} == Network.deallocate alloc1.ref, cluster

    assert {:ok, [alloc2]} == Network.allocations network.ref, cluster
    assert {:ok, [alloc2]} == Network.allocations slice.ref, cluster

    assert Network.networks(server1) === Network.networks(server2)
  end
end
