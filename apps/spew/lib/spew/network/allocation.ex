defmodule Spew.Network.Allocation do
  @moduledoc """
  Allocator for a given slice

  
  """

  @typedoc "The unique reference to a network"
  @type allocation :: String.t

  @doc "Inet address"
  @type address :: :inet.ip_address

  @doc "The state of the allocation"
  @type state :: :active | :inactive

  @typedoc "The owner of an allocation"
  @type owner :: {atom, String.t}

  @doc """
  The slice representing a IP Allocation

  ## Fields

    * `:ref` - the unique string used to identify the allocation
    * `:slice` - Reference to the network slice
    * `:owner` - The entity owning the allocation
    * `:state` - the activation state of the allocation
    * `:address` - The IP address of the allocation
    * `:tags` - List of tags assigned to this allocation
  """
  defstruct ref: "",
            owner: {nil, nil},
            state: :active,
            addresses: nil,
            tags: []

  @type t :: %__MODULE__{
    ref: allocation,
    owner: owner,
    state: :active | :inactive,
    addresses: [{:inet.ip_address, 0..128}],
    tags: [String.t]
  }

  alias __MODULE__
  alias Spew.Network.Slice
  alias Spew.Utils.Net.InetAddress

  @doc """
  Generate a reference for this allocation
  """
  @spec genref(Slice.slice, owner, boolean) :: allocation
  def genref(%Slice{ref: "slice-" <> ref} = slice, term, true = _external?) do
    "allocation-#{ref}/" <> genref(slice, term, false)
  end
  def genref(%Slice{}, term, false = _external?) do
    Spew.Utils.hash(term) |> String.slice(0, 8)
  end

  @doc """
  Allocate a address in the given `slice`
  """
  @spec allocate(Slice.slice, owner) :: {:ok, t} | {:error, term}
  def allocate(%Slice{ranges: ranges} = slice, owner) do
    spaceleft = Enum.reduce ranges, [], fn({ip, mask}, acc) ->
      ref = InetAddress.to_string(ip) <> "/#{mask}"
      maxsize = InetAddress.maxrange(ip) - 1
      allocated = map_size slice.allocations
      available = trunc(:math.pow(2, maxsize - mask)) - allocated

      if 0 === available do
        [ref | acc]
      else
        acc
      end
    end

    case spaceleft do
      [] ->
        ref = genref slice, owner, true
        intref = genref slice, owner, false
        case slice.allocations[intref] do
          %Allocation{ref: ref} ->
            {:error, {:conflict, {:allocations, [ref]}, slice.ref}}

          nil ->
            alloc = %Allocation{
              ref: ref,
              owner: owner,
              addresses:  Enum.map(ranges, &allocate2(slice.allocations, &1, owner, 1)),
              state: :active
            }

            {:ok, alloc}
        end

      exhausted ->
        {:error, {:exhausted, exhausted, slice.ref}}
    end
  end

  defp allocate2(allocations, {ip, mask} = inet, owner, n) do
    n = n + 1
    ip = InetAddress.increment ip, n
    if free? allocations, ip do
      {ip, mask}
    else
      # just loop until we find one...
      allocate2 allocations, inet, owner, n
    end
  end

  defp free?(allocations, ip) do
    not Enum.any? allocations, fn({_, allocation}) ->
      Enum.member? allocation.addresses, ip
    end
  end

  @doc """
  Disable a allocation
  """
  @spec disable(t) :: t
  def disable(%Allocation{} = alloc) do
    %{alloc | state: :inactive}
  end

  @doc """
  Enable a allocation
  """
  @spec enable(t) :: t
  def enable(%Allocation{} = alloc) do
    %{alloc | state: :inactive}
  end

  @doc """
  Tag allocation
  """
  @spec tag(t, [String.t]) :: t
  def tag(%Allocation{tags: oldtags} = alloc, tags) do
    %{alloc | tags: Enum.uniq(tags ++ oldtags)}
  end

  @doc """
  Untag a allocation
  """
  @spec untag(t, [String.t]) :: t
  def untag(%Allocation{tags: tags} = alloc, forremoval) do
    %{alloc | tags: Enum.filter(tags, fn(tag) -> ! Enum.member? forremoval, tag end)}
  end
end
