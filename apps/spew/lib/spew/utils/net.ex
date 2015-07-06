defmodule Spew.Utils.Net do
  @moduledoc """
  Utility functions for network
  """

  defmodule Iface do
    @moduledoc """
    Helper functions to work with interfaces
    """

    alias Spew.Utils.Net.InetAddress
    alias __MODULE__

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
          {:ok, split_params(opts, %__MODULE__{name: iface})}
      end
    end

    @doc """
    Remove a subnet `ranges` from `iface`
    """
    @spec remove_addrs(String.t, [{:inet.ip_address, 0..128}]) :: :ok | {:error, term}
    def remove_addrs(iface, ranges) do
      require Logger

      case stats iface do
        {:ok, %Iface{addrs: addrs}} ->
          cmds = Enum.filter_map ranges, fn({ip, mask}) ->
              ip = InetAddress.to_string ip
              Map.has_key?(addrs, ip) && addrs[ip][:netmask] === mask
            end,
            fn({ip, mask}) ->
              ip = InetAddress.to_string ip
              maybe_sudo ++ ["ip", "addr", "del", "local", "#{ip}/#{mask}", "dev", iface]
            end
        
          untilerr cmds, :ok, &syscmd/1

        {:error, _} = res ->
          res
      end
    end

    @doc """
    Ensure that the bridge `iface` is available with the ip ranges `ranges`
    """
    @spec ensure_bridge(String.t, [{:inet.ip_address, 0..128}]) :: :ok | {:error, term}
    def ensure_bridge(iface, ranges) do
      require Logger

      case stats iface do
        {:ok, %Iface{addrs: addrs}} ->
          # check my ranges
          errors = Enum.filter ranges, fn({ip, mask}) ->
            ip = InetAddress.to_string ip
            ! Map.has_key?(addrs, ip) || addrs[ip][:netmask] !== mask
          end

          case errors do
            [] ->
              cmds = [maybe_sudo ++ ["ip", "link", "set", "up", "dev", iface]]
              untilerr cmds, :ok, &syscmd/1

            errs ->
              Logger.error """
              iface[#{iface}]: configured but lacks setup for:
                #{Enum.map(ranges, fn({ip,mask}) -> "\t* #{InetAddress.to_string(ip)}/#{mask}\n" end)}
              current configuration:
                #{Enum.map(addrs, fn({_,%{addr: ip, netmask: mask}}) -> "\t* #{InetAddress.to_string(ip)}/#{mask}\n" end)}
              """

              {:error, {{:noaddr, errs}, {:iface, iface}}}
          end

        {:error, {:notfound, {:iface, _}}} ->
          addrs = Enum.map ranges, fn({ip, mask}) ->
            ip = InetAddress.to_string ip
            maybe_sudo ++ ["ip", "addr", "add", "local", "#{ip}/#{mask}", "dev", iface]
          end

          cmds = [maybe_sudo ++ ["brctl", "addbr", iface] | addrs]

          untilerr cmds, :ok, &syscmd/1
      end
    end

    @doc """
    Remove a bridge completely
    """
    @spec remove_bridge(String.t) :: :ok | {:error, term}
    def remove_bridge(iface) do
      cmds = [
        maybe_sudo ++ ["ip", "link", "set", "down", "dev", iface],
        maybe_sudo ++ ["brctl", "delbr", iface],
      ]
      untilerr cmds, :ok, &syscmd/1
    end

    defp syscmd([cmd | args]) do
      require Logger
      Logger.debug "exec #{Enum.join([cmd | args], " ")}"
      case System.cmd System.find_executable(cmd),
                      args,
                      [stderr_to_stdout: true] do

        {_buf, 0} ->
          :ok

        {buf, n} -> 
          {:error, {{:cmdexit, n}, [cmd | args], buf}}
      end
    end
    defp untilerr([], ret, _), do: ret
    defp untilerr([e | rest], ret, fun) do
      case fun.(e) do
        :ok -> untilerr rest, ret, fun
        res -> res
      end
    end

    defp maybe_sudo do
      case System.get_env("USER") do
        "root" -> []
        _ -> ["sudo"]
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
    def subnet({ip, _mask} = net, forwho), do: subnet(net, forwho, maxrange(ip))
    def subnet({_ip, mask}, _forwho, claim) when mask > claim do
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
