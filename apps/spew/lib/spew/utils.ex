defmodule Spew.Utils do
  def hash(vals) do
    :crypto.hash(:sha, :erlang.term_to_binary(vals))
      |> Base.encode16
      |> String.downcase
  end
end
