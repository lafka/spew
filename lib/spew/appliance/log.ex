defmodule Spew.Appliance.Log do
  @moduledoc """
  Writes to log
  """

  def init(appref) do
    statedir = Application.get_env(:spew, :appliance)[:statedir]
    logpath = Path.join [statedir, appref, "log"]
    logfile = Path.join [logpath, "console.log"]

    File.mkdir_p! logpath
    fd = File.open! logfile, [:append]

    %{logstream: fd, appref: appref, logfile: logfile, logpath: logpath}
  end

  def write(%{logstream: fd} = state, device, buf) when nil !== fd do
    IO.write fd, buf
    {:ok, state}
  end
  def write(state, _device, _buf), do: {:ok, state}

  def close(%{logstream: fd, logfile: file} = state) do
    File.close fd
    {:ok, state}
  end
  def close(%{} = state), do: {:ok, state}

  def cleanup(%{logstream: fd, logpath: dir} = state) do
    File.close fd
    File.rm_rf Path.dirname(dir)
    {:ok, state}
  end
end
