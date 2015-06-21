defmodule Spewbuild do
  @moduledoc """
  Functions related to finding, validating and preparing builds for
  running
  """

  @doc """
  Find all builds

  Takes one argument `pattern` which expects a string `<build>/<tag>`
  a '*' can be used as wildcard for any of the parts (ie. `riak/2.*`)

  Any more than two components will be discarded
  """
  def builds(pattern \\ "*/*", spewpath \\ nil) do
    pattern = case String.split pattern, "/" do
      [p1] -> p1 <> "/*"
      [p1, p2 | _] -> p1 <> "/" <> p2
    end

    spewpath = spewpath || Application.get_env(:spew, :buildpath) || []
    Enum.flat_map(spewpath, fn(path) ->
      paths = Path.wildcard Path.join([path, pattern, "**", "*.tar.gz"]) |> Path.expand
      Enum.map paths, &buildinfo/1
    end) |> Enum.into %{}
  end

  def tree(builds), do: tree(builds, true)
  def tree(builds, reference?), do: tree(builds, reference?, %{})
  def tree(builds, reference?, acc) do
    Enum.reduce builds, %{}, fn({k, build}, acc) ->
      val = if reference? do k else build end
      {target, vsn} = {build["TARGET"], build["VSN"]}
      newitem = Dict.put(acc[target] || %{}, vsn, [val | acc[target][vsn] || []])
      Dict.put(acc, target, newitem)
    end
  end

  def buildinfo(archive) do
    metafile = './SPEWMETA'
    {:ok, [{^metafile, buf}]} = :erl_tar.extract archive, [:memory, {:files, [metafile]}]
    meta = parsemeta(buf)
            |> Dict.put("ARCHIVE", archive)
            |> Dict.put("CHECKSUM", Path.basename(archive, ".tar.gz"))
            |> Dict.put("HOST", "#{node}")
            |> Dict.put("TYPE", "spew-archive-1.0")
    {meta["CHECKSUM"], meta}
  end

  defp parsemeta(buf) do
    pair String.split(buf, ["\n", "="], trim: true)
  end

  defp pair(pairs), do: pair(pairs, %{})
  defp pair([], acc), do: acc
  defp pair([k, v | rest], acc), do: pair(rest, Dict.put(acc, k, v))
end
