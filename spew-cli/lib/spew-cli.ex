defmodule SpewCLI do

  alias SpewCLI.Cmd

  @cmds [
    Cmd.Appliances,
    Cmd.Start,
    #Cmd.Stop,
    Cmd.Run,
    #Cmd.Kill,
    Cmd.Log,
    Cmd.Attach
  ]

  def main(["help", cmd | _]) do
    IO.puts callmod cmd, :help, []
  end
  def main(["help"]) do
    IO.puts """
    # spew-cli

    usage: spew-cli cmd [options] [args]

    args:
    #{for mod <- @cmds, do: "\t" <> mod.shorthelp <> "\n"}
    """
  end
  def main([cmd | args]) do
    callmod cmd, :run, args
  end
  def main(_), do: IO.puts(usage)


  def maybe_start_network() do
    name = :"spew-#{gen_ref}"

    :os.cmd('epmd -daemon')

    {:ok, _} = :net_kernel.start [name, :longnames]
    #[_, host] = "#{node}" |> String.split "@"
    host = "127.0.0.1"
    case :net_adm.ping :'spew@#{host}' do
      :pong ->
        :global.sync

      :pang ->
        message = "failed to connect to spew server: spew@#{host}"
        IO.puts :stderr, IO.ANSI.format([:red, :bright, message])
        System.halt 1
    end
  end

  def host do
    host = "127.0.0.1"
    :'spew@#{host}'
  end

  defp gen_ref do
    ref = :crypto.rand_bytes 32
    :crypto.hash(:sha256, :erlang.term_to_binary(ref))
      |> Base.encode16
      |> String.slice(0, 7)
      |> String.downcase
  end


  defp usage, do: "usage: spew-cli cmd [options] [args]"

  defp callmod(cmd, fun, args) do
    mod = :"#{__MODULE__}.Cmd.#{String.capitalize(cmd)}"
    Code.ensure_loaded mod

    if function_exported? mod, fun, 1 do
      apply mod, fun, [args]
    else
      IO.puts :stderr, "invalid command: #{cmd}"
      IO.puts :stderr, "Available commands:"
      for cmd <- @cmds do
        call = String.split("#{cmd}", ".") |> List.last |> String.downcase
        IO.puts "\t#{cmd.shorthelp}"
      end
    end
  end

end
