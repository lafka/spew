defmodule Spew.Utils do
  def hash(type \\ :sha, vals) do
    :crypto.hash(type, :erlang.term_to_binary(vals))
      |> Base.encode16
      |> String.downcase
  end
end
