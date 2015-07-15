defmodule Spew.Plugin.Instance.Build do
  @moduledoc """
  Plugin to automatically verify, unpack builds and cleanup builds
  """

  use Spew.Plugin

  require Logger

  alias Spew.Instance.Item
  alias Spew.Build
  alias Spew.Build.Server

  @doc """
  Spec for Build plugin
  """
  def spec(%Item{}) do
    alias Spew.Plugin.Instance.OverlayMount

    [
      require: [OverlayMount], # If we have a build we have a overlay
      before:  [OverlayMount]
    ]
  end

  @doc """
  Plugin init:
    - verify build
    - async unpack
  """
  def init(%Item{runtime: {:build, {:ref, buildref}}} = instance, _plugin, opts) do
    buildserver = opts[Server] || Build.server
    case Build.get buildref, buildserver do
      {:ok, build} ->
        targetdir = Path.join [Application.get_env(:spew, :spewroot), "build", build.ref]

        task = Task.async fn ->
          Build.Item.unpack build, targetdir
        end

        {:ok, %{
          buildref: buildref,
          rootdir: targetdir,
          unpacker: task,
          unpacked?: false
        }}
      {:error, err} ->
        {:error, {err, {:instance, instance.ref}}}
    end
  end
  def init(%Item{runtime: _} = instance, _plugin, _opts) do
    :ignore
  end

  @doc """
  No-op, builds are kept until manually removed.
  """
  def cleanup(instance, _state, _opts), do: :ok

  @doc """
  Handle plugin events
  """
  def notify(_instance, %{unpacker: task} = state, :start) do
    case state[:unpacked?] || Task.await task, :infinity do
      true ->
        :ok

      {:ok, _targetdir} ->
        {:update, %{state | unpacked?: true}}

      {:error, _} =res ->
        res
    end
  end
  def notify(_instance, _state, _ev), do: :ok
end
