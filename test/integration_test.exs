defmodule IntegrationTest do
  require Logger

  use ExUnit.Case, async: false

  alias Spew.Appliance.Config.Item

  test "client/server deployment" do
    {:ok, servercfgref} = Spew.Appliance.create "test-server", %Item{
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh /run.sh"],
        busybox?: true,
        root: {:archive, find_latest_build("server", "0.0.1")},
        network: [{:bridge, "tm"}]
      ]
    }

    {:ok, clientcfgref} = Spew.Appliance.create "test-client", %Item{
      type: :systemd,
      runneropts: [
        command: ["/bin/busybox sh /run.sh"],
        busybox?: true,
        root: {:archive, find_latest_build("client", "0.0.1")},
        network: [{:bridge, "tm"}]
      ]
    }

    {:ok, clientref} = Spew.Appliance.run "test-client", %{}, [subscribe: [:log]]
    {:ok, serverref} = Spew.Appliance.run "test-server", %{}, [subscribe: [:log]]

    #on_exit fn() ->
    #  Logger.debug "force exit for test-(client,ref)"

    #  Spew.Appliance.stop clientref, keep?: false, kill?: true
    #  Spew.Appliance.stop serverref, keep?: false, kill?: true
    #end

    assert_receive {:log, ^serverref, {:stdout, "ping\n"}}, 5000
    assert_receive {:log, ^clientref, {:stdout, "pong\n"}}, 5000
  end

  defp find_latest_build(target, vsn \\ "*") do
    case Path.wildcard "./test/integration/builds/#{target}/#{vsn}/*/*/*.tar.gz" do
      [] ->
        raise(ArgumentError, message: "no such build: ./test/integration/builds/#{target}/")

      paths ->
        [{_, path} | _] = Enum.map(paths, &({File.stat!(&1).ctime, &1})) |> Enum.sort
        path
    end
  end

  @max_mailbox_length 100

  @doc false
  def __mailbox__(pid) do
    {:messages, messages} = Process.info(pid, :messages)
    length = length(messages)
    mailbox = Enum.take(messages, @max_mailbox_length) |> Enum.map_join("\n", &inspect/1)
    mailbox_message(length, mailbox)
  end

  defp mailbox_message(0, _mailbox), do: ". The process mailbox is empty."
  defp mailbox_message(length, mailbox) when length > 10 do
    ". Process mailbox:\n" <> mailbox
      <> "\nShowing only #{@max_mailbox_length} of #{length} messages."
  end
  defp mailbox_message(_length, mailbox) do
    ". Process mailbox:\n" <> mailbox
  end
end
