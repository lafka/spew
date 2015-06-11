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

    case body[:appref] do
      nil ->
        send_resp conn, 400, encode(%{error: "no appref given"})

      appref ->
        case Discovery.add body[:appref], body do
          :ok ->
            send_resp conn, 201, encode(body)

          {:error, {:app_exists, ^appref}} ->
            case Discovery.update appref, body do
              {:ok, newbody} ->
                send_resp conn, 200, encode(newbody)

              err ->
                send_resp conn, 400, ""
            end

          err ->
            send_resp conn, 400, ""
        end
    end
  end

  get "/appliance" do
    {:ok, res} = Discovery.get []
    send_resp conn, 200, encode(res)
  end

  get "/appliance/:appspec" do
    case Discovery.Spec.from_string appspec do
      {:ok, res} ->
        {:ok, res} = Discovery.get res
        send_resp conn, 200, encode(res)

      {:error, err} ->
        Logger.debug "failed to parse: #{inspect appspec}"
        send_resp conn, 400, encode(%{error: inspect err})
    end
  end

  get "/subscribe" do
    {:ok, ref} = Discovery.subscribe true
    conn = send_chunked conn, 200

    case subloop ref, conn do
      {:ok, conn} ->
        conn

      {:error, conn, err} ->
        Logger.debug "subscribe/error: #{inspect err}"
        conn
    end
  end
  get "/subscribe/:appspec" do
    case Discovery.Spec.from_string appspec do
      {:ok, appspec} ->
        {:ok, ref} = Discovery.subscribe appspec
        conn = send_chunked conn, 200

        case subloop ref, conn do
          {:ok, conn} ->
            conn

          {:error, conn, err} ->
            Logger.debug "subscribe/error: #{inspect err}"
            conn
        end

      {:error, err} ->
        send_resp conn, 400, encode(%{error: inspect err})
    end
  end

  get "/await/:appspec" do
    case Discovery.Spec.from_string appspec do
      {:ok, appspec} ->
        sendchunks = fn(chunks, conn) ->
          Enum.reduce chunks, conn, fn(app, conn) ->
            Logger.debug "send chunk: #{encode app}"
            {:ok, conn} = chunk conn, "event: await.appliance\ndata: #{encode app}\n\n"
            conn
          end
        end

        {:ok, ref} = Discovery.subscribe appspec
        case Discovery.get appspec do
          {:ok, apps} ->

            {apps, rest} = fulfilled apps, appspec
            conn = send_chunked conn, 200
            conn = sendchunks.(apps, conn)

            await rest, conn, sendchunks

          {:error, {:query, err}} ->
            send_resp conn, 400, encode(%{error: inspect err})
        end

      {:error, err} ->
        send_resp conn, 400, encode(%{error: inspect err})
    end
  end

  defp await([], conn, _cont), do: conn
  defp await(specs, conn, cont) do
    receive do
      {:add, appref, appstate} ->
        {apps, rest} = fulfilled [appstate], specs
        await rest, cont.(apps, conn), cont

      {:update, appref, _oldappstate, appstate} ->
        {apps, rest} = fulfilled [appstate], specs
        await rest, cont.(apps, conn), cont

      # @todo should add delete in here to wait for service that are
      # added than deleted
    end
  end

  defp fulfilled(apps, specs) do
    Enum.reduce apps, {[], specs}, fn(app, {apps, specs}) ->
      case Discovery.Spec.match? app, specs do
        [] ->
          {apps, specs}

        matchedspecs  when is_list(specs) ->
          rest = Enum.reduce matchedspecs, specs, fn(spec, specs) ->
            {[app | apps], specs -- [spec]}
          end
      end
    end

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

      {:error, err}->
        {:error, conn, err}
    end
  end

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
