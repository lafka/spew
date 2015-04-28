defmodule SpewCLI do

  alias SpewCLI.Start

  def main(["help", cmd | _]) do
    IO.puts callmod cmd, :help, []
  end
  def main(["help"]) do
    IO.puts """
    # spew-cli

    usage: spew-cli cmd [options] [args]

    args:
      #{Start.shorthelp}
    """
  end
  def main([cmd | args]) do
    callmod cmd, :run, args
  end
  def main(_), do: IO.puts(usage)


  def maybe_start_network() do
    {:ok, _} = :net_kernel.start [:"#{gen_ref}"]
  end

  defp gen_ref do
    :crypto.hash(:sha256, :erlang.term_to_binary(make_ref))
      |> Base.encode16 |> String.slice(0, 16)
  end


  defp usage, do: "usage: spew-cli cmd [options] [args]"

  defp callmod(cmd, fun, args) do
    mod = :"#{__MODULE__}.#{String.capitalize(cmd)}"
    Code.ensure_loaded mod

    if function_exported? mod, fun, 1 do
      apply mod, fun, [args]
    else
      IO.puts :stderr, "invalid command: #{cmd}"
    end
  end

  defmodule Start do
    def run(args) do
      SpewCLI.maybe_start_network
    end

    def help(args) do
      """
      usage: spew-cli start [--all] | <ref-or-name1, .., ref-or-nameN>

      Starts one or more appliances, if --all is given everything is
      started otherwise those specified as arguments.

      Name can be the distinct name of the appliance or the reference
      to an already existing appliance.
      """
    end

    def shorthelp, do:
      "start <ref-or-name, .. | --all> - start appliances"
  end

end
