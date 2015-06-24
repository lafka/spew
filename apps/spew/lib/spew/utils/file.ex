defmodule Spew.Utils.File do
  @moduledoc """
  Common functions to work with files
  """

  @doc """
  Hash a file based on streaming API
  """
  def hash(type \\ :sha, file) do
    ctx = :crypto.hash_init type

    File.stream!(file, [], 2048)
      |> Enum.reduce(ctx, fn(buf, acc) ->
        :crypto.hash_update acc, buf
      end)
      |> :crypto.hash_final
      |> Base.encode16
      |> String.downcase
  end
end

