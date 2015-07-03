defmodule Spew.Utils.Net do
  @moduledoc """
  Utility functions for network
  """

  defmodule Iface do
    @moduledoc """
    Helper functions to work with interfaces
    """

    alias Spew.Utils.Net.InetAddress

    defstruct name: nil,
              flags: [],
              hwaddr: nil,
              addrs: %{}

    @doc """
    Get network interface stats
    """
    def stats(iface) do
      {:ok, ifaces} = :inet.getifaddrs

      case List.keyfind ifaces, '#{iface}', 0 do
        nil ->
          {:error, {:notfound, {:iface, iface}}}

        {_, opts} ->
          split_params opts, %__MODULE__{name: iface}
      end
    end

    defp split_params([], acc), do: acc
    defp split_params([{:addr, addr} = t | opts], acc) do
      {params, rest} = Enum.split_while opts, fn({:addr, _}) -> false;
                                                (_) -> true end

      type = 4 === :erlang.size(addr) && :inet || :inet6
      addrs = Map.put acc.addrs,
                      InetAddress.to_string(addr),
                      Enum.into([t | params], %{type: type}, fn
                        ({:netmask, mask}) -> {:netmask, InetAddress.netmask_to_cidr(mask)}
                        (tuple) -> tuple
                      end)
      split_params rest, %{acc | addrs: addrs}
    end
    defp split_params(opts, acc) do
      {params, rest} = Enum.split_while opts, fn({:addr,_}) -> false;
                                                (_) -> true end

      acc = Enum.reduce params, acc, fn
        ({:hwaddr = k, v}, acc) -> Map.put(acc, k, mac_to_string(v))
        ({k, v}, acc) -> Map.put(acc, k, v)
      end
      split_params rest, acc
    end

    defp mac_to_string(mac) do
      mac
        |> Enum.map(&Integer.to_string(&1, 16))
        |> Enum.join(":")
        |> String.downcase
    end
  end


  defmodule InetAddress do
    @moduledoc """
    Helper functions for ip addresses
    """

    use Bitwise

    import Kernel, except: [to_string: 1]

    @doc """
    Convert a erlang style ip address tuple to string

    This function is ip version agnostic and accepts both ip4 and ip6
    addresses
    """
    def to_string(ip) do
      case :inet_parse.ntoa ip  do
        {:error, _} = err ->
          err

        val ->
          String.downcase "#{val}"
      end
    end

    @doc """
    See `to_string/1`
    """
    def to_string!(ip) do
      case to_string ip do
        {:error, _} ->
          raise ArgumentError, message: "invalid ip address"

        val ->
          val
      end
    end

    @doc """
    Convert a string to erlang style ip addresses, ignoring CIDR
    notation if any
    """
    def parse(ip), do: :inet_parse.address '#{hd(String.split("#{ip}", "/"))}'

    @doc """
    See `parse/1`
    """
    def parse!(ip) do
      case parse ip do
        val when is_binary(val) ->
          val

        e ->
          raise ArgumentError, message: "invalid ip address: #{inspect e}"
      end
    end

    @doc """
    Convert a netmask to it's equivalant CIDR notation
    """
    def netmask_to_cidr(mask) do
      mask
        |> Tuple.to_list
        |> Enum.reduce("", fn(n, acc) -> Integer.to_string(n,2) <> acc end)
        |> String.replace("0", "")
        |> byte_size
    end

    @doc """
    Increment an ip address by `n`, use negative number to reduce
    """
    def increment({a, b, c, d}, by) do
      <<a,b,c,d>> = (:binary.decode_unsigned(<<a,b,c,d>>) + by)
                    |> :binary.encode_unsigned

      {a, b, c, d}
    end
    def increment({a, b, c, d, e, f, g, h}, by) do
      <<a :: size(16), b :: size(16), c :: size(16),
        d :: size(16), e :: size(16), f :: size(16),
        g :: size(16), h :: size(16)>> =
          (:binary.decode_unsigned(<<
              a :: size(16), b :: size(16), c :: size(16),
              d :: size(16), e :: size(16), f :: size(16),
              g :: size(16), h :: size(16) >>) + by)
            |> :binary.encode_unsigned

      {a, b, c, d, e, f, g, h}
    end

    @doc """
    Find a subnet of size `claim` in the `ip`/`mask` network
    If claim is not given use the max size for the address family
    """
    def subnet({ip, mask} = net, forwho), do: subnet({ip, mask}, forwho, maxrange(ip))
    def subnet({_ip, mask}, forwho, claim) when mask > claim do
      raise SubnetRangeException, message: "network claim to bug",
                                  range: mask,
                                  claim: claim
    end
    def subnet({ip, mask}, forwho, claim) do
      size = claim - mask

      hash = :crypto.hash(:sha, :erlang.term_to_binary(forwho))
              |> :binary.decode_unsigned

      where = hash &&& (trunc(:math.pow(2, size)) - 1)

      {increment(ip, where <<< (maxrange(ip) - claim)), claim}
    end

    @doc """
    Return the netsize for a address family
    """
    def maxrange({_,_,_,_}), do: 32
    def maxrange({_,_,_,_,_,_,_,_}), do: 128
  end
end
