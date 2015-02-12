defmodule Spew.Utils.Collection do
  # merge a into b
  def deepmerge(%{} = a, %{} = b) do
    Map.merge norm(b), norm(a), fn
      (_k, b1, a1) when is_map(a) and is_map(b) ->
        deepmerge(b1, a1)

      # default to overwrite value if not map/list
      (_k, _b1, a1) ->
        a1
    end
  end
  def deepmerge(a, []), do: a
  def deepmerge(a, [{_,_} | _] = b) when is_list(a) do
    Dict.merge a, b, fn
      (_k, b1, a1) when is_list(a) and is_list(b) ->
        deepmerge a1, b1

      # default to overwrite value if not map/list
      (_k, _b1, a1) ->
        a1
    end
  end
  def deepmerge(a, b) when is_list(a) and is_list(b) do
    Enum.concat(a, b) |> Enum.uniq
  end
  def deepmerge(_a, b), do: b

  defp norm(%{} = x), do: Map.delete(x, :__struct__)
  defp norm([]), do: %{}
  defp norm([{_,_}|_] = x), do: Enum.into(x, %{})
end
