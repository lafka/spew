defmodule Spew.Utils.String do
  @moduledoc """
  Utilities for working with strings
  """

  @doc """
  Tokenizes a string, splitting on space and preserving quoted
  expressions
  """
  def tokenize(buf), do: Enum.reverse(tokenize(buf, []))
  defp tokenize("", acc), do: acc
  defp tokenize(<<byte :: binary-size(1), rest :: binary()>>, acc) when byte in ["\"", "'"] do
    matched? = String.ends_with? rest, byte
    [token | rest] = case String.split rest, byte, parts: 2 do
      [string] when matched? -> [string]
      [string, rest] -> [string, rest]
      [_string] ->
        raise ArgumentError, message: "could not find matching quote `#{byte}`"
    end

    tokenize Enum.join(rest), [token | acc]
  end
  defp tokenize(buf, acc) do
    [token | rest] = String.split buf, " ", parts: 2, trim: true
    tokenize Enum.join(rest), [token | acc]
  end

end
