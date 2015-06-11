defmodule SpewBuild.Build do

  @moduledoc """
  Helper functions to find and extract spew-builds
  """

  require Logger

  def find(buildspec) do
    buildsdir = System.get_env("SPEW_BUILDS") || "~/.spew/builds"

    buildspec2 = case String.split(buildspec, "/") do
      [target] ->
        # find "latest" tag
        [tag | _] = File.ls! Path.join(buildsdir, target) |> Path.expand
        [target, tag]

      [_target | _] = spec ->
        spec
    end

    {parts, _} = (buildspec2 ++ ["*", "*", "*.tar.gz"]) |> Enum.split(5)
    path = Path.join [buildsdir | parts]

    case path |> Path.expand |> Path.wildcard do
      [] ->
        {:error, {:enoent, path}}

      archives ->
        res = Enum.reduce archives, [], fn(archive, acc) ->
          metafile = './SPEWMETA'
          {:ok, [{^metafile, buf}]} = :erl_tar.extract archive, [:memory, {:files, [metafile]}]
          [Dict.put(parsemeta(buf), "ARCHIVE", archive) | acc]
        end

        {:ok, res}
    end
  end

  def unpack(%{"ARCHIVE" => archive}, appref) do
    target = Path.join System.tmp_dir, "spew", appref, "root"

    Logger.debug """
    extracting archive:
      source: #{archive}
      target: #{target}
    """

    :erl_tar.extract archive, [{:cwd, target}]
    {:ok, target}
  end
  def unpack(_buildspec, _), do: {:error, :undefined_archive}

  defp parsemeta(buf) do
    pair String.split(buf, ["\n", "="], trim: true)
  end

  defp pair(pairs), do: pair(pairs, %{})
  defp pair([], acc), do: acc
  defp pair([k, v | rest], acc), do: pair(rest, Dict.put(acc, k, v))

end
