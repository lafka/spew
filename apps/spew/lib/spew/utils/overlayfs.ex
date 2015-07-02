defmodule Spew.Utils.OverlayFS do
  @moduledoc """
  Mount/unmount support for overlayfs
  """

  require Logger

  @cmdopts [stderr_to_stdout: true]

  @doc """
  Mount an overlay at `mountpoint` with `[upperdir | lowerdirs] = dirs` and `workdir`

  No checks are performed to see 
  """
  def mount(mountpoint, [upperdir | lowerdirs], workdir) do
    missingdirs = Enum.filter_map [mountpoint, upperdir, workdir, lowerdirs], fn(dir) ->
      ! File.dir? dir
    end, fn(dir) ->
      if File.exists? dir do {:enotdir, dir} else {:enoent, dir} end
    end

    case missingdirs do
      [] ->
        lowerdirs = Enum.join lowerdirs, ":"
        case System.cmd System.find_executable("sudo"),
                         ["mount", "-t", "overlay", "overlay", "-o",
                          "lowerdir=#{lowerdirs},upperdir=#{upperdir},workdir=#{workdir}",
                          mountpoint],
                         @cmdopts do
        {_buf, 0} ->
          :ok

        {err, code} ->
          Logger.warn "mount[#{mountpoint}]: failed to mount '#{err}'"
          {:error, {{:exit, code}, {:mountpoint, mountpoint}}}
        end

      dirs ->
        {:error, {{:dirs, dirs}, {:mountpoint, mountpoint}}}
    end
  end

  @doc """
  Check if `mountpoint` is mounted

  This only check any mount uses `mountpoint`, no check are done to
  see if it's an overlayfs mount or that some specific target is
  mounted there
  """
  def mounted?(mountpoint) do
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
  Unmount overlay `mountpoint` 
  """
  def unmount(mountpoint) do
    case System.cmd System.find_executable("sudo"),
                     ["unmount", "-t", mountpoint],
                     @cmdopts do
      {_buf, 0} ->
        :ok

      {err, code} ->
        Logger.warn "mount[#{mountpoint}]: failed to unmount"
        {:error, {:unmount, {:exit, code}, {:mountpoint, mountpoint}}}
    end
  end
end
