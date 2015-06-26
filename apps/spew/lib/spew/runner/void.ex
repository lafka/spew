defmodule Spew.Runner.Void do
  @moduledoc """
  A void runner that does not actually run anything
  """

  alias Spew.Instance.Item

  def capabilities, do: [
    :plugin
  ]

  def run(%Item{}) do
  end
end
