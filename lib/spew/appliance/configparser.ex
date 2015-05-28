defmodule Spew.Appliance.ConfigParser do

  @moduledoc """
  Parse configuration
  """

  alias Spew.Appliance.Config.Item

  def parse(file) do
    tree = File.stream!(file) |> Enum.reduce %{}, fn
      ("#" <> _, acc) -> acc
      ("\n", acc) -> acc
      (line, acc) ->
        [k, v] = String.split line, [" ", "\t"], parts: 2, trim: true
        keyparts = String.split k, "."
        insert_at keyparts, String.strip(v), acc
    end

    apps = Enum.into tree["app"], %{}, fn({k, v}) ->
      {app, _v} = {%Item{name: k}, v}
        |> map_type(k)
        |> map_depends
        |> map_target
        |> map_restart
        |> map_service
        |> map_runneropts

      app = Map.put app, :file, file
      cfgref = gen_ref(app)
      app = Map.put app, :cfgref, cfgref

      {cfgref, app}
    end

    {:ok, apps}
  end

  defp insert_at([k], val, acc), do:
    Dict.put(acc, k, val)
  defp insert_at([k | path], val, acc), do:
    Dict.put(acc, k, insert_at(path, val, acc[k] || %{}))

  defp map_type({item, %{"type" => "systemd"} = v}, _k), do:
    {%{item | :type => :systemd}, Dict.delete(v, "type")}
  defp map_type({item, %{"type" => "shell"} = v}, _k), do:
    {%{item | :type => :shell}, Dict.delete(v, "type")}
  defp map_type({item, %{"type" => "void"} = v}, _k), do:
    {%{item | :type => :void}, Dict.delete(v, "type")}
  defp map_type({item, v}, k), do:
    raise(ArgumentError, message: "invalid type: #{v["type"]} for key app.#{k}.type")

  defp map_depends({item, %{"depends" => deps} = v}) do
    deps = Enum.map String.split(deps, " "), fn
      ("service:" <> dep) ->
        {:service, dep}
    end

    {%{item | :depends => deps}, Dict.delete(v, "depends")}
  end
  defp map_depends(v), do: v

  defp map_target({item, %{"target" => target} = v}) do
    {app, appopts} = case String.split(target, "#") do
      [app] ->
        {String.strip(app), [type: :spew]}

      [app, appopts] ->
        appopts = pair String.split(appopts, [":", " ", "\t", ","], trim: true)
        appopts

        {String.strip(app), appopts}
    end

    {%{item | :appliance => [app, appopts]}, Dict.delete(v, "target")}
  end
  defp map_target(v), do: v

  defp pair(pairs), do: pair(pairs, %{})
  defp pair([], acc), do: acc
  defp pair([k, v | rest], acc), do: pair(rest, Dict.put(acc, k, v))

  defp map_restart({item, %{"restart" => restart} = v}) do
    Enum.map(String.split(restart, " "), &(String.to_atom(&1)))
    {%{item | :restart => restart}, Dict.delete(v, "restart")}
  end
  defp map_restart(v), do: v

  # no concept of service just yet
  #defp map_service({item, %{"service" => service} = v), do:
  #  {%{item | :service => service}, Dict.delete(v, "service")}
  #defp map_service(v), do: v
  defp map_service({item, v}), do: {item, Dict.delete(v, "service")}

  defp map_runneropts({item, v}) do
    {%{item | :runneropts =>
      Enum.into(v, [], fn({k,v}) ->
        {String.to_atom(k), String.split(v, " ")}
      end
    )}, %{}}
  end

  defp gen_ref(%Item{} = vals) do
    :crypto.hash(:sha256, :erlang.term_to_binary(vals)) |> Base.encode64
  end
end
