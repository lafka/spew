defmodule Spew.Utils.Time do
  @moduledoc """
  Utilities to work with time, mainly to start using new Time API of R18
  """

  @doc """
  Get now according to `unit`

  If a Erlang version < R18 is used only :native will be available
  """
  def now, do: now(:native)
  def now(:native) do
    if function_exported? :erlang, :timestamp, 0 do
      :erlang.timestamp
    else
      :erlang.now
    end
  end
  def now(unit), do: :erlang.system_time(unit)
end
