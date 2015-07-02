defmodule Spew.Utils.Time do
  @moduledoc """
  Utilities to work with time, mainly to start using new Time API of R18
  """

  @doc """
  Get now according to `unit`

  If a Erlang version < R18, it will fallback to :erlang.now/1
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

  @doc """
  Get monotonic time

  If a Erlang version < R18, :erlang.now/1 will be used
  """
  def monotonic, do: monotonic(:native)
  def monotonic(unit) do
    if unit !== :native and function_exported? :erlang, :monotonic_time, 1 do
      :erlang.monotonic_time :native
    else
      :erlang.now
    end
  end
end
