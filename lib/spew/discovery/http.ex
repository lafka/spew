defmodule Spew.Discovery.HTTP do
  use Plug.Router

  import Plug.Conn

  require Logger

  alias Spew.Discovery

  plug Plug.Logger

  plug :match
  plug :dispatch

  post "/appliance" do
    {:ok, body, conn} = read_body conn
    body = decode body

    case Discovery.add body[:appref], body do
      :ok ->
        send_resp conn, 201, ""

      err ->
        IO.inspect err
        send_resp conn, 400, ""
    end
  end

  get "/appliance" do
    {:ok, res} = Discovery.get []
    send_resp conn, 200, encode(res)
  end

  get "/appliance/:appspec" do
    case Discovery.get parseappspec(appspec) do
      {:ok, res} ->
        send_resp conn, 200, encode(res)

      {:error, err} ->
        send_resp conn, 400, encode(%{error: err})
    end
  end

  # thhis must atleast iterate a million times over each byte :|
  defp parseappspec(buf), do: parseappspec(buf, [])
  defp parseappspec("", acc), do: acc
  defp parseappspec(buf, acc) do
    [k, buf] = String.split buf, ":", parts: 2
    {v, rest} = case String.split buf, ";", parts: 2 do
      [v] -> {v, ""}
      [v, rest] -> {v, rest}
    end

    parseappspec rest, [{String.to_existing_atom(k), parseappspec2(v)} | acc]
  end

  get "/subscribe/:appspec" do
    {:ok, ref} = Discovery.subscribe parseappspec appspec
    conn = send_chunked conn, 200
    subloop ref, conn
  end

  defp subloop(ref, conn) do
    res = receive do
      {:add, appref, appstate} ->
        chunk conn, "event: appliance.add\ndata: #{encode appstate}\n\n"

      {:update, appref, oldappstate, appstate} ->
        chunk conn, "event: appliance.update\ndata: #{encode %{old: oldappstate, new: appstate}}\n\n"

      {:delete, appref, appstate} ->
        chunk conn, "event: appliance.delete\ndata: #{encode appstate}\n\n"

      {:plug_conn, :sent} ->
        {:ok, conn}

      {:cowboy_req, :resp_sent} ->
        {:ok, conn}

      x ->
        Logger.error "discovery/http[#{ref}] unknown ev: #{inspect x}"
        {:ok, conn}
    end
    case res do
      {:ok, conn} ->
        subloop ref, conn
      res ->
        res
    end
  end

  defp parseappspec2(buf), do: parseappspec2(buf, {"", []})

  defp parseappspec2("", {acc, group}), do:
    [acc | group]

  defp parseappspec2("," <> rest, {"", group}), do:
    parseappspec2(rest, {"", group})
  defp parseappspec2("," <> rest, {k, group}), do:
    parseappspec2(rest, {"", [k | group]})

  defp parseappspec2("(" <> rest, {"", group}) do
    {rest, innergroup} = parseappspec2 rest
    parseappspec2 rest, {"", [innergroup | group]}
  end
  defp parseappspec2("(" <> rest, {acc, group}) do
    {rest, innergroup} = parseappspec2 rest
    parseappspec2 rest, {"", [innergroup | group]}
  end
  defp parseappspec2(")" <> rest, {acc, group}), do:
    {rest, [acc|group]}

  defp parseappspec2(<<k :: binary-size(1), rest :: binary()>>, {acc, group}), do:
    parseappspec2(rest, {acc <> k, group})


  #defp parseappspec(buf) do
  #  String.split(buf, ";") |> Enum.reduce, [], fn(part) ->
  #    [k, v] = String.split part, ":", parts: 2
  #    parseappspec2 String.split(v, "("), acc
  #  end
  #end
  #defp parseappspec2("", acc), do: acc
  #defp parseappspec2(buf, group) do
  #  case String.split buf, ")" do
  #    [parts] -> String.split 
  #  end
  #end

  put "/appliance/:appref" do
    {:ok, body, conn} = read_body conn
    body = decode body

    case Discovery.update appref, body do
      {:ok, body} ->
        send_resp conn, 200, encode(body)

      err ->
        send_resp conn, 400, ""
    end
  end

  delete "/appliance/:appref" do
    case Discovery.delete appref do
      :ok ->
        send_resp conn, 410, ""

      {:error, {:not_found, ^appref}} ->
        send_resp conn, 404, encode(%{error: "not found",
                                      appref: appref})
    end
  end

  match _ do
    send_resp(conn, 404, "{\"error\":\"no route\"}")
  end

  defp encode(body), do: Poison.encode!(body)
  defp decode(body), do: Poison.decode!(body, keys: :atoms)
end
