defmodule SpewNetworkTest do
  use ExUnit.Case

  alias Spew.Network

  test "claim network slice" do
    # this test ONLY checks that we are repeatedly given the same
    # slice as long as the hostname stays the same. There is no check
    # to see if this is already claimed, or any functions to
    # statically assign networks

    assert {:ok, %{ranges: [{{172, 21, 26, 0}, 25},
                  {{64512, 16384, 4, 0, 20993, 51363, 16384, 0}, 100}]}}
          = Network.range "spew", "break if hashfun or network cfg changes"
  end

  test "auto allocate spewhost" do
    alias Spew.Network.InetAllocator
    alias Spew.Utils.Net.InetAddress
    alias Spew.Network.InetAllocator.Allocation
    alias Spew.Network.InetAllocator.Server

    {:ok, server} = Server.start_link name: __MODULE__
    {:ok, [%Allocation{} = spew]} = InetAllocator.query {:owner, :spew}, server
    assert :spew == spew.owner
    assert node == spew.host

    {:ok, %{ranges: [{ip4, 25},
                  {ip6, 100}]}}
          = Network.range "spew"

    addrs = [InetAddress.increment(ip4, 1), InetAddress.increment(ip6, 1)]

    # iface already has one defined  address, we only check for the
    # existance of our own
    Enum.each addrs, fn(addr) ->
      assert Enum.member?(spew.addrs, addr), "addr not configured #{InetAddress.to_string(addr)}"
    end
  end

  test "allocate / deallocate / get" do
    alias Spew.Network.InetAllocator
    alias Spew.Network.InetAllocator.Allocation
    alias Spew.Network.InetAllocator.Server

    {:ok, server} = Server.start_link name: __MODULE__

    owner = {:instance, "inet-allocate-test"}

    {:ok, %Allocation{} = item} = InetAllocator.allocate "spew", owner, server

    assert {:ok, item} == InetAllocator.allocate "spew", owner, server
    assert :ok == InetAllocator.deallocate item.ref, server
    assert {:error, {:notfound, {:inetallocation, _}}} = InetAllocator.get item.ref, server

    assert {:ok, item} == InetAllocator.allocate "spew", owner, server
    assert {:ok, item} == InetAllocator.get item.ref, server
  end
end
