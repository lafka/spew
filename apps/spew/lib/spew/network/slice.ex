defmodule Spew.Network.Slice do
  @doc """
  Subnet definition
  """
  @type subnet :: {:inet.ip_address, 0..128}

  @typedoc """
  The unique reference to a network
  """
  @type slice :: String.t

  @typedoc "The owner of an allocation"
  @type owner :: {atom, String.t}

  @doc """
  The slice representing a  Network Delegation

  ## Fields

    * `:ref :: slice` - the unique string used to identify the slice
    * `:iface` - The name of the iface for this slice
    * `:owner` - the owning entity of this network slice
    * `:ranges` - List of subnets delegated to this slice
    * `:allocations :: [Spew.Network.Allocation.t]` - Map of ip allocations
    * `:active :: bool` - State of the network slice
  """
  defstruct ref: nil,
            owner: nil,
            iface: nil,
            ranges: [],
            allocations: %{},
            active: true

  @type t :: %__MODULE__{
    ref: slice,
    iface: String.t | nil,
    owner: owner,
    ranges: %{},
    allocations: %{},
    active: boolean
  }


  alias __MODULE__
  alias Spew.Network
  alias Spew.Utils.Net.InetAddress

  def genref(%Network{ref: "net-" <> ref} = network, term, true = _external?) do
    "slice-#{ref}/" <> genref(network, term, false)
  end
  def genref(%Network{}, term, _external?) do
    Spew.Utils.hash(term) |> String.slice(0, 8)
  end

  def delegate(%Network{ranges: []} = network, _opts) do
    {:error, {:noranges, {:network, network.ref}}}
  end
  def delegate(%Network{ranges: ranges} = network, opts) do
    exhausted = Enum.reduce ranges, [], fn({ip, mask, claim}, acc) ->
      ref = InetAddress.to_string(ip) <> "/#{mask}"
      available = trunc(:math.pow(2, claim - mask)) - map_size(network.slices)
      if 0 === available do
        [ref | acc]
      else
        acc
      end
    end

    case exhausted do
      [] ->
        owner = opts[:owner] || node
        slice = %Slice{
          ref: genref(network, owner, true),
          iface: opts[:iface] || network.iface,
          owner: owner,
          ranges: Enum.map(ranges, fn({ip, mask, claim}) ->
                    InetAddress.subnet({ip, mask}, owner, claim)
                  end),
          allocations: %{}
        }

        {:ok, {genref(network, owner, false), slice}}

      exhausted ->
        {:error, {:exhausted, exhausted, network.ref}}
    end
  end


  def parserange({_,_,_} = range), do: range
  def parserange(range) do
    [ip, mask, claim] = case String.split range, ["/", "#"] do
      [ip] -> [ip, nil, nil]
      [ip, mask] -> [ip, mask, nil]
      [ip, mask, claim] -> [ip, mask, claim]
    end

    {:ok, ip} = InetAddress.parse ip

    {mask, ""} = Integer.parse(mask || defaultmask(ip))
    {claim, ""} = Integer.parse(claim || defaultclaim(mask))

    {ip, mask, claim}
  end

  defp defaultmask({10,0,_,_}), do: 8
  defp defaultmask({172,n,_,_}) when n in 16..31, do: 12
  defp defaultmask({192,168,_,_}), do: 16
  defp defaultmask({_,_,_,_}), do: 24
  defp defaultmask({_,_,_,_,_,_,_,_}), do: 104

  defp defaultclaim(n), do: n - 2

end
