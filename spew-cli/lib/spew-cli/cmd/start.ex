defmodule SpewCLI.Cmd.Start do
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

