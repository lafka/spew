defmodule Spew.Network do
  @moduledoc """
  Support for automating some network work

  The module is responsible for automatically assigning subnets to a
  host when it starts up AND to make sure there are not to many
  conflicts.

  In essence spew will define a set of networks, the networks have
  one or more address spaces it can use (ip6 and ip4).
  The node name will use the hash of the hostname then use the `claim`
  parameter from the network to see how big slice of the network it
  should claim.  Most cases this will work fine since there will be
  a large network (/16, /12, or /8) to take items from.

  To make sure there are no collisions spew will check if it's in
  cluster mode, and if so it will wait to spawn instances until it
  has been able to sync the network table with atleast one other node

  ## Initial Network setup

  For convenience, and until the API is less vague, this module also
  has some helper functions to setup the initial bridge, it does not
  make any assumptions on how addresses are delegated within that
  space but they can easily be passed on to a running instance

  ## IP allocation & DNS

  When a instance is created a IP address will be allocated either by
  finding it in the `spewhosts` file or by randomly selecting a unused
  address from the host network slice.

  The spewhosts file can be bind mounted by a runner to provide unicast
  lookup for hosts.
  """

  require Logger

  use Bitwise

  alias Spew.Utils.Net.Iface
  alias Spew.Utils.Net.InetAddress

  defmodule NetRangeException do
    defexception message: nil,
                 range: nil,
                 claim: nil
  end

  @doc """
  Return list of available networks
  """
  def list do
    networks = Application.get_env(:spew, :provision)[:networks]
    Enum.map networks, fn({net, opts}) ->
      {net, opts[:iface]}
    end
  end

  @doc """
  Find the preferred network slice

  Generate the preferred network ranges based on available networks
  in config. This DOES NOT guarantee that the network slice is
  not already in use by any other hosts.

  @todo 2015-07-01 lafka; check the local hosts file for previous info
  """
  def range(network, host \\ node) do
    case Application.get_env(:spew, :provision)[:networks][network] do
      nil ->
        {:error, {:notfound, {:network, network}}}

      %{range: range} = network ->
        slices = Enum.map range, fn
          (line) ->
            {ip, mask, claim} = parserange line
            if mask > claim do
              raise NetRangeException, message: "network claim to big",
                                       range: mask,
                                       claim: claim
            end

            size = claim - mask
            hash = :crypto.hash(:sha, :erlang.term_to_binary(host))
              |> :binary.decode_unsigned

            where = hash &&& (:erlang.trunc(:math.pow(2, size)) - 1)

            {InetAddress.increment(ip, where <<< (spacesize(ip) - claim)), claim}
        end

        {:ok, %{ranges: slices, iface: network[:iface] || network}}

      _ ->
        {:error, {:input, :range_or_claim_missing, {:network, network}}}
    end
  rescue
    e in NetRangeException ->
      {:error, {:netrange, e, {:network, network}}}
  end

  defp parserange({_,_,_} = res), do: res
  defp parserange("" <> range) do
    [ip, mask, claim] = String.split range, ["/", "#"]
    {:ok, ip} = :inet_parse.address '#{ip}'
    {mask, ""} = Integer.parse mask
    {claim, ""} = Integer.parse claim
    {ip, mask, claim}
  rescue e in MatchError ->
    raise NetRangeException, message: "invalid range"
  end

  defp spacesize({_,_,_,_}), do: 32
  defp spacesize({_,_,_,_,_,_,_,_}), do: 128

  @doc """
  Calls the correct system commands to setup the initial bridge

  This does offcourse require root access, however if the bridge is
  already up with the correct configuration there's not need.

  @todo provide utility scripts to configure the bridge to avoid
  general sudo overuse in spew itself. could even put it in spewtils
  """
  def setupbridge(network, host \\ node) do
    {:ok, net} = range network, host
    case check_bridge net.iface, net.ranges do
      :notfound ->
        case create_bridge net.iface do
          true ->
            configure_iface(net.iface, net.ranges)

          {:error, n} ->
            {:error, {:createbr, {:exit, n}, {:iface, net.iface}}}
        end

      :invalidcfg ->
        Logger.warn "iface[#{net.iface}] bridge already exists but with invalid config, maybe its in use?"
        configure_iface(net.iface, net.ranges)

      :ok ->
        # Ensure iface is up
        configure_iface net.iface, []
    end
  end

  defp create_bridge(iface) do
    case syscmd ["sudo", "brctl", "addbr", iface] do

      {_, 0} -> true
      {_, n} -> {:error, n}
    end
  end

  defp configure_iface(iface, []) do
    case syscmd ["sudo", "ip", "link", "set", "up", "dev", iface] do
      {_, 0} -> true
      {_, n} -> {:error, :linkup, {:exit, n}, {:iface, iface}}
    end
  end
  defp configure_iface(iface, [{addr, mask} | slice]) do
    addr = InetAddress.increment addr, 1
    addr = :inet_parse.ntoa addr

    case syscmd ["sudo", "ip", "addr", "add", "local", "#{addr}/#{mask}", "dev", iface] do
      {_, 0} -> configure_iface iface, slice
      {_, 2} -> configure_iface iface, slice
      {_, n} -> {:error, :addrset, {:exit, n}, {:iface, iface}}
    end
  end

  defp check_bridge(iface, slices) do
    {:ok, ifaces} = :inet.getifaddrs
    case Iface.stats iface do
      {:error, {:notfound, {:iface, ^iface}}} ->
        :notfound

      %Iface{addrs: addrmap, flags: flags} ->
        matched? = Enum.all? slices, fn({addr, mask}) ->
          addr = InetAddress.increment addr, 1
          addr = InetAddress.to_string addr
          Map.has_key?(addrmap, addr) and addrmap[addr][:netmask] === mask
        end

        if matched? and Enum.member?(flags, :up) do
          :ok
        else
          :invalidcfg
        end
    end
  end

  defp syscmd([cmd | args] = call) do
    Logger.debug "syscmd: #{Enum.join(call, " ")}"
    System.cmd System.find_executable(cmd), args, [stderr_to_stdout: true]
  end

end
