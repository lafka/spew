defmodule Spew.Appliance.ConfigParser do

  require Logger

  @moduledoc """
  Parse configuration
  """

  alias Spew.Appliance.Config.Item

  def parse(file) do
    Logger.debug "#{__MODULE__} processing: #{file}"
    {cfgs, apps} = File.stream!(file) |> Enum.reduce {%{}, %{}}, fn
      ("#" <> _, acc) ->
        Process.put :line_num, Process.get(:line_num, 0) + 1
        acc

      ("\n", acc) ->
        Process.put :line_num, Process.get(:line_num, 0) + 1
        acc

      # this is an actual appliance configuration
      ("*" <> line = raw, {cfgacc, appacc}) ->
        Process.put :line_num, Process.get(:line_num, 0) + 1
        Process.put :line, raw
        [k, v] = String.split line, [" ", "\t"], parts: 2, trim: true
        [app | _] = keyparts = String.split k, "."

        cfgacc = Dict.put_new cfgacc, app, %Item{name: app}
        cfgacc = line keyparts, String.strip(v), cfgacc, cfgacc
        {cfgacc, appacc}

      # this is the instance config
      (line, {cfgacc, appacc}) ->
        Process.put :line_num, Process.get(:line_num, 0) + 1
        Process.put :line, line


        [k, v] = String.split line, [" ", "\t"], parts: 2, trim: true
        [app | _] = keyparts = String.split k, "."

        appacc = Dict.put_new appacc,
                              app,
                              %{:name => app,:cfgrefs => {nil, []}}
        appacc = line keyparts, String.strip(v), appacc, cfgacc

        {cfgacc, appacc}
    end

    Process.delete :line
    Process.delete :line_num

    {:ok, cfgs, apps}
  rescue e in [ArgumentError, MatchError] ->
    IO.write "failed to process #{file}:#{Process.get(:line_num)}\nline: #{Process.get(:line)}"
    IO.puts Exception.format_stacktrace
    {:error, e}
  end

  defp line(k, v, acc), do: line(k, v, acc, %{})
  defp line([app, "derive"], "*" <> cfgname, acc, cfgacc) do
    case cfgacc[cfgname] do
      nil ->
        raise ArgumentError, message: "no such cfg: #{cfgname}"

      %{cfgrefs: {_ancestorref, ancestorrefs}} = ancestor ->

        item = Spew.Utils.deepmerge ancestor, acc[app]
        item = %{item |
          :cfgrefs => {app, [cfgname | ancestorrefs]},
          :name => acc[app].name
        }

        Map.put acc, app, item
     end
  end
  defp line([_app, "derive"], _cfgname, _acc, _cfgacc), do:
    raise(ArgumentError, message: "refusing to derive a instance (did you forget the `*` in front?)")

  defp line([app, "type"], type, acc, _cfgacc) when type in ["systemd", "void", "shell"] do
    Map.put acc, app, Map.put(acc[app], :type, String.to_atom(type))
  end
  defp line([_app, "type"] = k , type, _acc, _cfgacc), do:
    raise(ArgumentError, message: "invalid type #{type} for #{inspect k}")

  defp line([app, "depends"], deps, acc, _cfgacc) do
    deps = Enum.map String.split(deps, " "), fn
      ("service:" <> dep) ->
        {:service, dep}
    end

    Map.put acc, app, Map.put(acc[app], :depends, deps)
  end

  defp line([app, "target"], target, acc, _cfgacc) do
    {targetapp, targetappopts} = case String.split(target, "#") do
      [targetapp] ->
        {String.strip(targetapp), %{type: "spew"}}

      [targetapp, targetappopts] ->
        targetappopts = pair String.split(targetappopts, [":", " ", "\t", ","], trim: true)

        {String.strip(targetapp), targetappopts}
    end

    Map.put acc, app, Map.put(acc[app], :appliance, [targetapp, targetappopts])
  end

  defp line([app, "service"], service, acc, _cfgacc) do
    Map.put acc, app, Map.put(acc[app], :service, service)
  end

  defp line([app, "appliance"], appliance, acc, _cfgacc) do
    Map.put acc, app, Map.put(acc[app], :appliance, [appliance, []])
  end

  defp line([app, "restart"], strategy, acc, _cfgacc) do
    strategy = Enum.map(String.split(strategy, " "), &(String.to_atom(&1)))
    Map.put acc, app, Map.put(acc[app], :restart, strategy)
  end

  defp line([app, "$", k], v, acc, _cfgacc) do
    insert_at([app, :runneropts, String.to_atom(k)], String.split(v), acc)
  end
  defp line([app, "runneropts"], v, acc, _cfgacc) do
    insert_at([app, :runneropts], String.split(v), acc)
  end

  defp line([app | key], v, _acc, _cfgacc) do
    raise ArgumentError, message: "unknown definition: #{Enum.join(key, ".")}"
  end


  defp insert_at([k], val, acc) when is_map(acc) do
    Map.put(acc, k, val)
  end
  defp insert_at([k | path], val, acc) when is_map(acc) do
    Map.put(acc, k, insert_at(path, val, Map.get(acc, k) || %{}))
  end
  defp insert_at([k], val, acc) do
    Dict.put(acc, k, val)
  end
  defp insert_at([k | path], val, acc) do
    Dict.put(acc, k, insert_at(path, val, Dict.get(acc, k) || %{}))
  end


  defp pair(pairs), do: pair(pairs, %{})
  defp pair([], acc), do: acc
  defp pair([k, v | rest], acc), do: pair(rest, Dict.put(acc, String.to_atom(k), v))
end
