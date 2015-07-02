defmodule Spewbuild do
  @moduledoc """
  Functions related to finding, validating and preparing builds for
  running
  """

  require Logger


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
    Logger.debug "builds: scanning #{pattern} in #{inspect spewpath}"

    Enum.flat_map(spewpath, fn(path) ->
      globpath = Path.join([path, pattern, "**", "*.{tar,tar.gz}"]) |> Path.expand
      paths = Path.wildcard(globpath)
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
            |> Map.put("ARCHIVE", archive)
            |> Map.put("CHECKSUM", hash(:sha256, archive))
            |> Map.put("HOST", "#{node}")
            |> Map.put("TYPE", "spew-archive-1.0")
            |> Map.put("SIGNATURE", archive <> ".asc")

    hash = Spew.Utils.File.hash archive

    {hash, meta}
  end

  defp parsemeta(buf) do
    pair String.split(buf, ["\n", "="], trim: true)
  end

  defp pair(pairs), do: pair(pairs, %{})
  defp pair([], acc), do: acc
  defp pair([k, v | rest], acc), do: pair(rest, Dict.put(acc, k, v))

  # From Spew.Utils.File.hash/2
  defp hash(type \\ :sha, file) do
    ctx = :crypto.hash_init type

    File.stream!(file, [], 2048)
      |> Enum.reduce(ctx, fn(buf, acc) ->
        :crypto.hash_update acc, buf
      end)
      |> :crypto.hash_final
      |> Base.encode16
      |> String.downcase
  end
end
