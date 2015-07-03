defmodule Spew.InstancePlugin.OverlayChroot do
  @moduledoc """
  Mount/unmount support for overlayfs
  """

  defmodule Mount do
    @moduledoc """
    Utility to help mounting overlayfs
    """

    require Logger
    alias __MODULE__

    @type mountpoint :: Path.t

    defstruct mountpoint: nil,
              upperdir: nil,
              lowerdirs: [],
              workdir: nil

    @type t :: %__MODULE__{
      mountpoint: mountpoint,
      upperdir: Path.t,
      lowerdirs: [Path.t],
      workdir: Path.t
    }

    @cmdopts [stderr_to_stdout: true]

    @doc """
    Mount an overlay at `mountpoint` with `[upperdir | lowerdirs] = dirs` and `workdir`
    """
    @spec mount(mountpoint, [Path.t], Path.t) :: {:ok, t} | {:error, term}
    def mount(mountpoint, [upperdir | lowerdirs], workdir) do
      missingdirs = Enum.filter_map [mountpoint, upperdir, workdir, lowerdirs], fn(dir) ->
        ! File.dir? dir
      end, fn(dir) ->
        if File.exists? dir do {:enotdir, dir} else {:enoent, dir} end
      end

      case missingdirs do
        [] ->
          lowerdirs2 = Enum.join lowerdirs, ":"
          case System.cmd System.find_executable("sudo"),
                           ["mount", "-t", "overlay", "overlay", "-o",
                            "lowerdir=#{lowerdirs2},upperdir=#{upperdir},workdir=#{workdir}",
                            mountpoint],
                           @cmdopts do
          {_buf, 0} ->
            {:ok, %Mount{mountpoint: mountpoint,
                         lowerdirs: lowerdirs,
                         upperdir: upperdir,
                         workdir: workdir}}

          {err, code} ->
            Logger.warn "mount[#{mountpoint}]: failed to mount '#{err}'"
            {:error, {{:exit, code}, {:mountpoint, mountpoint}}}
          end

        dirs ->
          {:error, {{:dirs, dirs}, {:mountpoint, mountpoint}}}
      end
    end

    @doc """
    Check if overlay is  mounted

    This only check any mount uses `mountpoint`, no check are done to
    see if it's an overlayfs mount or that some specific target is
    mounted there
    """
    @spec mounted?(t) :: boolean
    def mounted?(%Mount{mountpoint: mountpoint}) do
      case System.cmd System.find_executable("mountpoint"),
                       [mountpoint],
                       @cmdopts do
        {_buf, 0} ->
          true

        {_err, _code} ->
          false
      end
    end

    @doc """
    Unmount overlay specified by `mount`
    """
    @spec unmount(t) :: :ok | {:error, term}
    def unmount(%Mount{mountpoint: mountpoint}) do
      case System.cmd System.find_executable("sudo"),
                       ["unmount", "-t", "overlay", mountpoint],
                       @cmdopts do
        {_buf, 0} ->
          :ok

        {err, code} ->
          Logger.warn "mount[#{mountpoint}]: failed to unmount"
          {:error, {:unmount, {:exit, code}, {:mountpoint, mountpoint}}}
      end
    end
  end


  require Logger

  alias Spew.Instance.Item

  def dependant(%Item{runtime: runtime} = instance) do
    case runtime do
      {:build, _} ->
        [
          after: Spew.InstancePlugin.Build,
          require: Spew.InstancePlugin.Build, # require build plugin to run
        ]

      _ ->
        []
    end
  end

  def setup(_instance, _) do
    raise Exception, message: "unsupported plugin"
  end

  def start(%Item{ref: ref,
                  plugin: %{__MODULE__ => state}} = instance, opts) do
    raise Exception, message: "unsupported plugin"
  end

  def event(%Item{}, state, _ev), do: state

  def call(%Item{}, %Mount{} = state, {:instance, ref, :preinit}) do
    Logger.debug "instance[#{ref}]: creating overlay on #{state.mountpoint}"
    :ok
  end
  def call(%Item{}, state, _ev), do: state
end
