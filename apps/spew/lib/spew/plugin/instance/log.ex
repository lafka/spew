defmodule Spew.InstancePlugin.Log do
  @moduledoc """
  Add support for logging io of
  """

  require Logger

  alias Spew.Instance.Item

  def setup(_instance, _) do
    raise Exception, message: "unsupported plugin"
  end

  @doc """
  Start the log plugin, currently unsupported
  """
  def start(%Item{ref: ref,
                  plugin: %{__MODULE__ => state}} = instance, opts) do
    raise Exception, message: "unsupported plugin"
  end

  def event(%Item{plugin: %{ __MODULE__ => _}}, state, _ev), do: state
end

