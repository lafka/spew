defmodule Spew.Plugin.Instance.OverlayMount do
  @moduledoc """
  Plugin to automatically create a overlay mount for a chroot or a
  build
  """

  use Spew.Plugin

  require Logger

  alias Spew.Instance.Item

  @doc """
  Spec for Build plugin
  """
  def spec(%Item{}) do
    alias Spew.Plugin.Instance.Build

    [
      after:  [Build] # run before on load, and after on cleanup
    ]
  end

  defstruct mountpoint: nil,
            overlaydir: nil,
            lowerdirs: [],
            workdir: nil

  @typep t :: %__MODULE__{
    mountpoint: Path.t,
    overlaydir: Path.t,
    lowerdirs: [Path.t],
    workdir: Path.t
  }

  alias __MODULE__, as: Mountpoint

  @doc """
  Plugin init:
    - create required directories
  """
  def init(%Item{} = instance, _plugin, _opts) do
    Logger.debug "instance[#{instance.ref}]: init plugin #{__MODULE__}"
    basedir = Path.join [Application.get_env(:spew, :spewroot), "instance", instance.ref]
    mount = %Mountpoint{
      mountpoint: Path.join(basedir, "rootfs"),
      overlaydir: Path.join(basedir, "overlay"),
      workdir: Path.join(basedir, "work")
    }

    File.mkdir_p! mount.mountpoint
    File.mkdir_p! mount.overlaydir
    File.mkdir_p! mount.workdir

    {:ok, mount}
  rescue e in File.Error ->
    {:error, e}
  end

  @doc """
  Cleanup build:
    - Ensure everything is unmounted
  """
  def cleanup(%Item{ref: ref} = instance, %Mountpoint{} = mount, _opts) do
    Logger.debug "instance[#{ref}]: cleanup after plugin #{__MODULE__}"
    unmount instance, mount
  end

  @doc """
  Handle plugin events
    - on :start the mount is created
    - on {:stop, _} unmount is called
  """
  def notify(%Item{} = instance, %Mountpoint{} = mount, {:stop, _}) do
    unmount instance, mount
  end

  def notify(%Item{} = instance, %Mountpoint{} = mount, :start) do
    ensure_mount instance, mount
  end

  def notify(_instance, %Mountpoint{} = _mount, _ev), do: :ok

  defp ensure_mount(%Item{ref: ref} = instance, %Mountpoint{mountpoint: mountpoint} = mount) do
    [cmd | args] = ["mount"]
    case System.cmd System.find_executable(cmd), args, [stderr_to_stdout: true] do
      {buf, 0} ->
        case Regex.run ~r/\w* on #{mountpoint}.*\n/, buf do
          [match] ->
            case String.split match, " " do
              ["overlay", "on", ^mountpoint, "type", "overlay", opts] ->

                lowerdirs = case pick_lowerdirs instance do
                  {:ok, lowerdirs} -> lowerdirs
                  {:error, _} -> []
                end

                match = String.split(opts, ~r/[(),]/, trim: true)
                  |> Enum.reduce %Mountpoint{mountpoint: mountpoint}, fn
                    ("lowerdir=" <> dirs, acc) ->
                      %{acc | lowerdirs: String.split(dirs, ":")}

                    ("upperdir=" <> dir, acc) ->
                      %{acc | overlaydir: dir}

                    ("workdir=" <> dir, acc) ->
                      %{acc | workdir: dir}

                    (_, acc) ->
                      acc
                  end

                if match == %{mount | lowerdirs: lowerdirs} do
                  :ok
                else
                  Logger.warn """
                  mount[#{mountpoint}]: overlay already mounted
                    existing: #{inspect match}
                    netmount: #{inspect %{mount | lowerdirs: lowerdirs}}
                  """
                  {:error, {:mountopts, {:mountpoint, mountpoint}}}
                end

              [source, "on", ^mountpoint, _opts] ->
                Logger.warn "mount[#{mountpoint}]: already mounted with #{source}"
                {:error, {:mountopts, {:mountpoint, mountpoint}}}
            end

          nil ->
            mount instance, mount
        end

      {_buf, n} ->
        {:error, {{:exit, n}, {:mountpoint, mountpoint}}}
    end
  end


  defp mount(%Item{ref: ref} = instance, %Mountpoint{} = mount) do
    # pull lowerdir from chroot / build info
    case pick_lowerdirs instance do
      {:ok, lowerdirs} ->
        Logger.debug """
        instance[#{ref}]: mounting
          mountpoint: #{mount.mountpoint}
          lowerdirs:  #{Enum.join(lowerdirs, ", ")}
          overlay:    #{mount.overlaydir}
          workdir:    #{mount.workdir}
        """

        [cmd | args] = maybe_sudo ++ ["mount", "-t", "overlay", "overlay", "-o",
                        "lowerdir=#{Enum.join(lowerdirs, ":")},upperdir=#{mount.overlaydir},workdir=#{mount.workdir}",
                        mount.mountpoint]

        Logger.debug "instance[#{ref}]: exec #{Enum.join([cmd|args], " ")}"
        case System.cmd System.find_executable(cmd), args, [stderr_to_stdout: true] do
          {_, 0} ->
            :ok

          {buf, n} ->
            Logger.warn "instance[#{ref}]: failed to unmount: #{mount.mountpoint}, #{buf}"
            {:error, {:exit, n}}
        end

        {:update, %{mount | lowerdirs: lowerdirs}}

      {:error, _} = res ->
        res

      nil ->
        :ok
    end
  end

  defp pick_lowerdirs(%Item{runtime: {:chroot, chroot}}) do
    if File.dir? chroot do
      {:ok, [chroot]}
    else
      {:error, {:enoent, chroot}}
    end
  end

  defp pick_lowerdirs(%Item{runtime: {:build, chroot}}) do
    {:error, {:buildsnotintegrate}}
  end

  defp pick_lowerdirs(%Item{runtime: nil}) do
    nil
  end

  defp mounted?(%Mountpoint{mountpoint: mountpoint}) do
    [cmd | args] = ["mountpoint", mountpoint]

    case System.cmd System.find_executable(cmd), args, [stderr_to_stdout: true] do
      {_, 0} ->
        true

      {_buf, n} ->
        false
    end
  end

  defp unmount(%Item{ref: ref}, %Mountpoint{} = mount) do
    Logger.debug "instance[#{ref}]: trying to unmount #{mount.mountpoint}"

    [cmd | args] = maybe_sudo ++ ["umount", "-t", "overlay", mount.mountpoint]

    Logger.debug "instance[#{ref}]: exec #{Enum.join([cmd|args], " ")}"
    case System.cmd System.find_executable(cmd), args, [stderr_to_stdout: true] do
      {_, n} when n in [0, 32] ->
        :ok

      {buf, n} ->
        Logger.warn "instance[#{ref}]: failed to unmount: #{mount.mountpoint}, #{buf}"
        {:error, {:exit, n}}
    end
  end

  defp maybe_sudo do
    case System.get_env("USER") do
      "root" -> []
      _ -> ["sudo"]
    end
  end
end
