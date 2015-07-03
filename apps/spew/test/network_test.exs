defmodule SpewNetworkTest do
  use ExUnit.Case

  alias Spew.Network
  alias Spew.Network.Server
  alias Spew.Network.Slice

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
    initopts = [networks: [%Network{name: "auto-add"}]]
    {:ok, server} = Server.start_link name: :"#{ctx[:test]}", init: initopts

    assert {:ok, [%Network{name: "auto-add"}]} = Network.networks server
  end


  test "join / leave / die / rejoin", ctx do
    name = "join/leave"
    network = %Network{name: name}
    {:ok, server1} = Server.start name: :"#{ctx[:test]}-1", init: [name: "server-1", networks: [network]]
    {:ok, server2} = Server.start name: :"#{ctx[:test]}-2", init: [name: "server-2", networks: [network]]

    {:ok, [network]} = Network.networks server1

    # First join the server1 to itself, the join it to server2
    # this should
    :ok = Network.join server1, network.ref, server1
    :ok = Network.join server1, network.ref, server2

    assert {:ok, _, %{"server-1" => {server1, :ok}, "server-2" => {server2, :ok}}} = Network.cluster network.ref, server1
    assert {:ok, _, %{"server-1" => {server1, :ok}, "server-2" => {server2, :ok}}} = Network.cluster network.ref, server2

    monref = Process.monitor server1
    Process.exit server1, :kill

    receive do
      {:DOWN, ^monref, :process, _pid, _} ->
        assert {:ok, _, %{"server-1" => {_, :down}, "server-2" => {_, :ok}}} = Network.cluster network.ref, server2
    after
      1000 -> exit(:exit)
    end

    # restart and state should converge when we join. There is (yet)
    # kept any state between crashes so no auto-rejoin
    # state between crashes
    {:ok, server1} = Server.start name: :"#{ctx[:test]}-1", init: [name: "server-1"]
    :ok = Network.join server1, network.ref, server2
    assert {:ok, _, %{"server-1" => {^server1, :ok}, "server-2" => {^server2, :ok}}} = Network.cluster network.ref, server2
  end


  test "slice delegation (delegate, slices, slice, undelegate)", ctx do
    name = "slice-delegation"
    network = %Network{name: name,
                       ranges: ["172.16.0.0/12#24"]}

    {:ok, server} = Server.start name: ctx[:test], init: [networks: [network]]
    {:ok, [network]} = Network.networks server

    {:ok, slice} = Network.delegate network.ref, "slice", server
    sliceref = slice.ref
    assert {:error, {:conflict, {:slices, [sliceref]}, "net-" <> _}} =Network.delegate network.ref, "slice", server

    assert {:ok, slice} == Network.slice slice.ref, server

    assert {:ok, [slice]} == Network.slices network.ref, server
    assert {:ok, %Slice{active: false}} = Network.undelegate slice.ref, server
    assert {:error, {:notfound, sliceref}} == Network.slice slice.ref, server
  end

  test "inet allocatation (allocate, deallocate, allocation, allocations)", ctx do
    name = "ip-allocation"
    network = %Network{name: name,
                       ranges: ["172.16.0.0/12#24"]}

    {:ok, server} = Server.start name: ctx[:test], init: [networks: [network]]
    {:ok, [network]} = Network.networks server
    {:ok, slice} = Network.delegate network.ref, "slice", server

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
    range = "172.16.0.0/29"
    network = %Network{name: name,
                       ranges: ["#{range}#30", "172.16.0.0/24#27"]}

    {:ok, server} = Server.start name: ctx[:test], init: [networks: [network]]
    {:ok, [network]} = Network.networks server

    {:ok, _slice1} = Network.delegate network.ref, "slice-1", server
    {:ok, _slice2} = Network.delegate network.ref, "slice-2", server
    assert {:error, {:exhausted, [range], network.ref}} == Network.delegate network.ref, "slice-3", server
  end


  test "slice over-allocation", ctx do
    # what happens when there are no more space to allocate in a slice
    name = "slice-over-allocation"
    network = %Network{name: name,
                       ranges: ["172.16.0.0/29#30"]}

    {:ok, server} = Server.start name: ctx[:test], init: [networks: [network]]
    {:ok, [network]} = Network.networks server
    {:ok, slice} = Network.delegate network.ref, "slice-1", server
    {ip, mask} = hd slice.ranges
    range = InetAddress.to_string(ip) <> "/#{mask}"

    {:ok, _alloc} = Network.allocate slice.ref, "addr-1", server
    {:ok, _alloc} = Network.allocate slice.ref, "addr-2", server
    assert {:error, {:exhausted, [range], slice.ref}} == Network.allocate slice.ref, "addr-3", server
  end


#  test "auto allocate spewhost" do
#    alias Spew.Network.InetAllocator
#    alias Spew.Utils.Net.InetAddress
#    alias Spew.Network.InetAllocator.Allocation
#    alias Spew.Network.InetAllocator.Server
#
#    {:ok, server} = Server.start_link name: __MODULE__
#    {:ok, [%Allocation{} = spew]} = InetAllocator.query {:owner, :spew}, server
#    assert :spew == spew.owner
#    assert node == spew.host
#
#    {:ok, %{ranges: [{ip4, 25},
#                  {ip6, 100}]}}
#          = Network.range "spew"
#
#    addrs = [InetAddress.increment(ip4, 1), InetAddress.increment(ip6, 1)]
#
#    # iface already has one defined  address, we only check for the
#    # existance of our own
#    Enum.each addrs, fn(addr) ->
#      assert Enum.member?(spew.addrs, addr), "addr not configured #{InetAddress.to_string(addr)}"
#    end
#  end
#
#  test "allocate / deallocate / get" do
#    alias Spew.Network.InetAllocator
#    alias Spew.Network.InetAllocator.Allocation
#    alias Spew.Network.InetAllocator.Server
#
#    {:ok, server} = Server.start_link name: __MODULE__
#
#    owner = {:instance, "inet-allocate-test"}
#
#    {:ok, %Allocation{} = item} = InetAllocator.allocate "spew", owner, server
#
#    assert {:ok, item} == InetAllocator.allocate "spew", owner, server
#    assert :ok == InetAllocator.deallocate item.ref, server
#    assert {:error, {:notfound, {:inetallocation, _}}} = InetAllocator.get item.ref, server
#
#    assert {:ok, item} == InetAllocator.allocate "spew", owner, server
#    assert {:ok, item} == InetAllocator.get item.ref, server
#  end

#  test "multi-node allocation", ctx do
#    alias Spew.Network
#    alias Spew.Network.Server
#
#    initopts = [networks: network = "multi-node"]
#
#    {:ok, node1} = Server.start_link name: name1 = :"#{ctx[:test]}-1", init: initopts
#    {:ok, node2} = Server.start_link name: name2 = :"#{ctx[:test]}-2", init: initopts
#    {:ok, node3} = Server.start_link name: name3 = :"#{ctx[:test]}-3", init: initopts
#
#    # allocate a slice on each host
#    {:ok, net} = Network.add %Network{name: "multi-node", 
#                                      ranges: ["10.64.0.0/10#24"]}
#
#    # Yay, zoidberg made distributed things!!!
#    {:ok, net} = Network.get "multi-node", node1
#    assert {:ok, net} == Network.get "multi-node", node2
#    assert {:ok, net} == Network.get "multi-node", node3
#
#
#    # Join the network
#    {:ok, slice1} = Network.newslice net.ref, name1
#    {:ok, slice2} = Network.newslice net.ref, name2
#    {:ok, slice3} = Network.newslice net.ref, name3
#
#    # Everyone agrees on the network topology
#    {:ok, net} = Network.get "multi-node", node1
#    assert {:ok, net} == Network.get "multi-node", node2
#    assert {:ok, net} == Network.get "multi-node", node3
#
#    # allocate some addresses in each slice, picking "random" servers
#    # to check that state is synced
#    allocations = Enum.flat_map(0..25, fn(n) ->
#      {:ok, alloc1} = Network.allocate slice1, "node-#{slice1.ref}-#{n}", node2
#      {:ok, alloc2} = Network.allocate slice2, "node-#{slice2.ref}-#{n}", node1
#      {:ok, alloc3} = Network.allocate slice3, "node-#{slice2.ref}-#{n}", node3
#      [alloc1, alloc2, alloc3]
#    end) |> Enum.sort
#
#    {:ok, %Network{} = network} = Network.get "multi-node"
#
#    {:ok, netallocs} = Network
#  end
#
end
