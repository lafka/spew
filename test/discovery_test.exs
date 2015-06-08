defmodule DiscoveryTests do

  defmodule DiscoveryIntegrationTest do
    # Test that running/stopping appliances actually generates events

    use ExUnit.Case, async: false

    alias Spew.Discovery
    alias Spew.Appliance

    setup do
      Spew.Discovery.flush
    end

    test "manager integration" do
      {parent, pref} = {self, make_ref}
      t = Task.async fn ->
        {:ok, ref} = Discovery.subscribe true
        send parent, {pref, :ok}
        a = receive do x -> x after 1000 -> {:error, :timeout} end
        b = receive do x -> x after 1000 -> {:error, :timeout} end
        c = receive do x -> x after 1000 -> {:error, :timeout} end
        {ref, [a, b, c]}
      end

      :ok = receive do {^pref, :ok} -> :ok after 1000 -> :timeout end

      {:ok, appref} = Appliance.run nil, %{name: "void", type: :void}
      :ok = Appliance.stop appref, keep?: false

      {_subref, [{:add, ^appref, %{}},
               {:delete, ^appref, %{}},
               {:error, :timeout}]} = Task.await t
    end
  end

  defmodule DiscoveryHTTPAPITest do
    use ExUnit.Case, async: false
    use Plug.Test

    alias Spew.Discovery.HTTP
    alias Spew.Discovery
    @opts HTTP.init([])

    setup do
      Spew.Discovery.flush
    end

    test "create and read" do
      appref = "create-and-read"
      conn = run :post, "/appliance", %{appref: appref,
                                        state: "waiting"}

      assert conn.state == :sent
      assert conn.status == 201
      assert conn.resp_body == ""
    end

    test "create and update" do
      appref = "create-and-update"

      run :post, "/appliance", %{appref: appref,
                                 state: "waiting"}

      conn = run :put, "/appliance/#{appref}", %{appref: appref,
                                                 state: "running"}

      assert conn.state == :sent
      assert conn.status == 200
      assert %{appref: ^appref, state: "running"} = conn.resp_body
    end

    test "create and delete" do
      appref = "create-and-delete"

      # fail on non existing
      conn = run :delete, "/appliance/no-such-appref"

      assert conn.state == :sent
      assert conn.status == 404
      assert %{error: "not found", appref: "no-such-appref"} = conn.resp_body

      # existing should work
      run :post, "/appliance", %{appref: appref,
                                 state: "waiting"}

      conn = run :delete, "/appliance/#{appref}"

      assert conn.state == :sent
      assert conn.status == 410
      assert "" = conn.resp_body
    end

    test "query" do
      :ok = Discovery.add "query-0", %{state: "waiting"}
      :ok = Discovery.add "query-1", %{state: "running"}
      :ok = Discovery.add "query-2", %{state: "waiting", tags: ["a"]}
      :ok = Discovery.add "query-3", %{state: "waiting", tags: ["b"]}
      :ok = Discovery.add "query-4", %{state: "running", tags: ["a", "b"]}
      :ok = Discovery.add "query-5", %{state: "waiting", tags: ["c"]}

      assert ["query-0", "query-2", "query-3", "query-5"] = qresp run(:get, "/appliance/state:waiting")
      assert ["query-3", "query-4"] = qresp run(:get, "/appliance/tags:b")
      assert ["query-3"] = qresp run(:get, "/appliance/tags:(!a,b)")
      assert ["query-4"] = qresp run(:get, "/appliance/tags:(a,b)")
      assert ["query-0", "query-1", "query-3", "query-4", "query-5"] = qresp run(:get, "/appliance/tags:!a,b")
      assert ["query-3", "query-5"] = qresp run(:get, "/appliance/tags:c,(!a,b)")
      assert ["query-4"] = qresp run(:get, "/appliance/tags:b;state:running")
      assert ["query-3"] = qresp run(:get, "/appliance/tags:b;state:waiting")
    end

    test "appref subscribe" do
      :inets.start()
      opts = Application.get_env(:spew, :discovery)
      ip = (opts[:opts][:ip] || {127, 0, 0, 1}) |> Tuple.to_list |> Enum.join "."
      port = case {opts[:schema], opts[:opts][:port]} do
        {:https, nil} -> 443
        {:http, nil} -> 80
        {_schema, port} -> port
      end

      appref = "appref-subscribe"
      url = '#{opts[:schema] || "http"}://#{ip}:#{port}/subscribe/appref:#{appref}'

      {:ok, ref} = :httpc.request :get, {url, []}, [], [{:sync, :false}, {:stream, :self}]
      receive do
        {:http, {^ref, :stream_start, headers}} ->
          assert 'chunked' = :proplists.get_value 'transfer-encoding', headers
      end

      :ok = Discovery.add appref, %{state: "waiting"}

      receive do
        {:http, {^ref, :stream, "event: appliance.add\ndata: " <> buf}} ->
          assert %{appref: ^appref, state: "waiting"} = decode(buf)
      end
    end

    defp qresp(resp) do
      for(i <- resp.resp_body, do:
        i.appref) |> Enum.sort
    end

    defp run(method, uri) do
      req = conn(method, uri) |> HTTP.call @opts

      if "" !== req.resp_body do
        Map.put req, :resp_body, decode(req.resp_body)
      else
        req
      end
    end

    defp run(method, uri, body) do
      req = conn(method, uri, encode(body))
        |> put_req_header("content-type", "application/json")

      req = HTTP.call req, @opts

      if "" !== req.resp_body do
        Map.put req, :resp_body, decode(req.resp_body)
      else
        req
      end
    end

    defp encode(body), do: Poison.encode!(body)
    defp decode(body), do: Poison.decode!(body, keys: :atoms)
  end

  defmodule DiscoveryErlAPITest do
    use ExUnit.Case, async: false

    alias Spew.Discovery

    setup do
      Discovery.flush
    end

    test "create and read" do
      appref = "create-and-read"
      :ok = Discovery.add appref, %{state: "waiting"}
      {:ok, [%{state: "waiting", appref: ^appref}]} = Discovery.get appref
    end

    test "create and update" do
      appref = "create-and-update"
      :ok = Discovery.add appref, %{state: "waiting"}
      {:ok, %{state: "running", appref: ^appref}} = Discovery.update appref, %{state: "running"}
      {:error, {:invalid_state, _state}} = Discovery.update appref, %{state: "wrong"}
      {:ok, [%{state: "running", appref: ^appref}]} = Discovery.get appref
    end

    test "create and delete" do
      appref = "create-and-delete"
      :ok = Discovery.add appref, %{state: "waiting"}
      :ok = Discovery.delete appref
      {:error, {:not_found, ^appref}} = Discovery.get appref
    end

    test "query" do
      :ok = Discovery.add "query-0", %{state: "waiting"}
      :ok = Discovery.add "query-1", %{state: "running"}
      :ok = Discovery.add "query-2", %{state: "waiting", tags: ["a"]}
      :ok = Discovery.add "query-3", %{state: "waiting", tags: ["b"]}
      :ok = Discovery.add "query-4", %{state: "running", tags: ["a", "b"]}
      :ok = Discovery.add "query-5", %{state: "waiting", tags: ["c"]}

      assert ["query-0", "query-2", "query-3", "query-5"] = qresp Discovery.get state: "waiting"
      assert ["query-3", "query-4"] = qresp Discovery.get tags: ["b"]
      assert ["query-3"] = qresp Discovery.get tags: [["!a", "b"]]
      assert ["query-4"] = qresp Discovery.get tags: [["a", "b"]]
      assert ["query-0", "query-1", "query-3", "query-4", "query-5"] = qresp Discovery.get tags: ["!a", "b"]
      assert ["query-3", "query-5"] = qresp Discovery.get tags: ["c", ["!a", "b"]]
      assert ["query-4"] = qresp Discovery.get tags: ["b"], state: "running"
      assert ["query-3"] = qresp Discovery.get tags: ["b"], state: "waiting"
    end

    defp qresp({:ok, resp}) do
      for(i <- resp, do:
        i.appref) |> Enum.sort
    end
    defp qresp(resp), do: resp

    test "appref subscription" do
      appref = "appref-subscribe"

      {parent, pref} = {self, make_ref}
      t = Task.async fn ->
        {:ok, ref} = Discovery.subscribe appref
        send parent, {pref, :ok}
        {ref, receive do x -> x after 1000 -> {:error, :timeout} end}
      end

      :ok = receive do {^pref, :ok} -> :ok after 1000 -> :timeout end

      :ok = Discovery.add appref, %{state: "waiting"}
      {ref, {:add, ^appref, appstate}} = Task.await t

      # Process died, ensure subscription is removed
      assert {:error, {:not_found, ^ref}} = Discovery.unsubscribe ref


      :ok = Discovery.flush

      t = Task.async fn ->
        {:ok, ref}= Discovery.subscribe appref

        y  = receive do {:add, _, _} = x -> x after 1000 -> {:error, :timeout} end
        y2 = receive do {:update, _, _old, _new} = x -> x after 1000 -> {:error, :timeout} end
        y3 = receive do {:delete, _, _} = x -> x after 1000 -> {:error, :timeout} end

        :ok = Discovery.unsubscribe ref

        y4 = receive do x -> x after 1000 -> {:error, :timeout} end
        [y, y2, y3, y4]
      end

      :ok = Discovery.add appref, %{state: "waiting"}
      {:ok, _} = Discovery.update appref, %{state: "running"}
      :ok = Discovery.delete appref
      :ok = Discovery.add appref, %{state: "waiting"}

      assert [
        {:add, ^appref, appstate},
        {:update, ^appref, appstate, newappstate},
        {:delete, ^appref, newappstate},
        {:error, :timeout}] = Task.await t
    end

    # test subscribing with more advanced "queries"
    # In case of update events these subscriptions are always matched
    # on both the new and old state of the event, the events though
    # are only sent once
    test "query subscription" do
      appref = "query-subscribe"

      {parent, pref} = {self, make_ref}
      t = Task.async fn ->
        {:ok, ref} = Discovery.subscribe [state: "running"]
        send parent, {pref, :ok}
        a = receive do x -> x after 1000 -> {:error, :timeout} end
        b = receive do x -> x after 1000 -> {:error, :timeout} end
        {ref, [a, b]}
      end

      :ok = receive do {^pref, :ok} -> :ok after 1000 -> :timeout end

      :ok = Discovery.add appref, %{state: "waiting"}
      {:ok, _} = Discovery.update appref, %{state: "running"}
      {:ok, _} = Discovery.update appref, %{state: "stopped"}

      {_ref, [{:update, ^appref, _old, %{state: "running"}},
             {:update, ^appref, %{state: "running"}, %{state: "stopped"}}]} = Task.await t

      Discovery.flush

      {parent, pref} = {self, make_ref}
      t = Task.async fn ->
        {:ok, ref} = Discovery.subscribe [tags: ["a", "b", ["c", "a"]]]
        send parent, {pref, :ok}
        a = receive do x -> x after 1000 -> {:error, :timeout} end
        b = receive do x -> x after 1000 -> {:error, :timeout} end
        c = receive do x -> x after 1000 -> {:error, :timeout} end
        d = receive do x -> x after 1000 -> {:error, :timeout} end
        {ref, [a, b, c, d]}
      end

      :ok = receive do {^pref, :ok} -> :ok after 1000 -> :timeout end

      :ok = Discovery.add appref, %{state: "waiting", tags: ["a", "b"]}
      {:ok, _} = Discovery.update appref, %{tags: ["c"]}
      {:ok, _} = Discovery.update appref, %{tags: ["c", "a"]}

      {_ref, [{:add, ^appref, %{tags: ["a", "b"]}},
             {:update, ^appref, %{tags: ["a", "b"]}, %{tags: ["c"]}}, # repeated
             {:update, ^appref, %{tags: ["c"]}, %{tags: ["c", "a"]}},
             {:error, :timeout}]} = Task.await t
    end
  end
end
