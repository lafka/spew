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

  For convenience, and until the API is less vague, this module also
  has some helper functions to setup the initial bridge, it does not
  make any assumptions on how addresses are delegated within that
  space but they can easily be passed on to a running instance
  """

  require Logger

  use Bitwise

  alias Spew.Utils.Net.InetAddress

  defmodule NetRangeException do
    defexception message: nil,
                 range: nil,
                 claim: nil
  end

  @doc """
  Find the preferred network slice

  Generate the preferred network ranges based on available networks
  in config. This DOES NOT guarantee that the network slice is
  not already in use by any other hosts.
  """
  def netslice(network, host \\ node) do
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

            {ipadd(ip, where <<< (spacesize(ip) - claim)), claim}
        end

        {:ok, slices}

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

  defp ipadd({a, b, c, d}, where) do
    <<a,b,c,d>> = (:binary.decode_unsigned(<<a,b,c,d>>) + where)
                  |> :binary.encode_unsigned

    {a, b, c, d}
  end
  defp ipadd({a, b, c, d, e, f, g, h}, where) do
    <<a :: size(16), b :: size(16), c :: size(16),
      d :: size(16), e :: size(16), f :: size(16),
      g :: size(16), h :: size(16)>> =
        (:binary.decode_unsigned(<<
            a :: size(16), b :: size(16), c :: size(16),
            d :: size(16), e :: size(16), f :: size(16),
            g :: size(16), h :: size(16) >>) + where)
          |> :binary.encode_unsigned

    {a, b, c, d, e, f, g, h}
  end

  @doc """
  Calls the correct system commands to setup the initial bridge

  This does offcourse require root access, however if the bridge is
  already up with the correct configuration there's not need.

  @todo provide utility scripts to configure the bridge to avoid
  general sudo overuse in spew itself. could even put it in spewtils
  """
  def setupbridge(network, host \\ node) do
    {:ok, slices} = netslice network, host
    case check_bridge network, slices do
      :notfound ->
        case create_bridge(network) do
          true ->
            configure_iface(network, slices)

          {:error, n} ->
            {:error, {:createbr, {:exit, n}, {:network, network}}}
        end

      :invalidcfg ->
        Logger.warn "network[#{network}] bridge already exists but with invalid config, maybe its in use?"
        configure_iface(network, slices)

      :ok ->
        # Ensure iface is up
        configure_iface network, []
    end
  end

  defp create_bridge(name) do
    case System.cmd System.find_executable("sudo"),
                    ["brctl", "addbr", name],
                    [stderr_to_stdout: true] do

      {_, 0} -> true
      {_, n} -> {:error, n}
    end
  end

  defp configure_iface(network, []) do
    case System.cmd System.find_executable("sudo"),
                    ["ip", "link", "set", "up", "dev", network],
                    [stderr_to_stdout: true] do
      {_, 0} -> true
      {_, n} -> {:error, :linkup, {:exit, n}, {:network, network}}
    end
  end
  defp configure_iface(network, [{ip, mask} | slice]) do
    address = :inet_parse.ntoa(ip)

    case System.cmd System.find_executable("sudo"),
                    ["ip", "addr", "add", "local", "#{address}/#{mask}", "dev", network],
                    [stderr_to_stdout: true] do

      {_, 0} -> configure_iface network, slice
      {_, 2} -> configure_iface network, slice
      {_, n} -> {:error, :addrset, {:exit, n}, {:network, network}}
    end
  end

  defp check_bridge(network, slices) do
    {:ok, ifaces} = :inet.getifaddrs
    case List.keyfind ifaces, '#{network}', 0 do
      nil ->
        :notfound

      {_, opts} ->
        addrmap = pick_inet_items  opts

        matched? = Enum.all? slices, fn({addr, mask}) ->
          Map.has_key?(addrmap, addr) and addrmap[addr] === mask
        end

        if matched? and Enum.member?(opts[:flags], :up) do
          :ok
        else
          :invalidcfg
        end
    end
  end

  defp pick_inet_items(opts), do: pick_inet_items(opts, %{})
  defp pick_inet_items([], acc), do: acc
  defp pick_inet_items([{:addr, addr}, {:netmask, mask} | rest], acc) do
      pick_inet_items rest, Map.put(acc, addr, InetAddress.netmask_to_cidr(mask))
  end
  defp pick_inet_items([_ | rest], acc), do: pick_inet_items(rest, acc)
end
