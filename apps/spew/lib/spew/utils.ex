defmodule Spew.Utils do
  def hash(vals) do
    :crypto.hash(:sha256, :erlang.term_to_binary(vals))
  end
end
