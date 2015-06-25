defmodule Spewpanel.BuildView do
  use Spewpanel.Web, :view

  alias Spew.Appliance

  def expand_build(build) do
    buildref = build.ref
    {:ok, appliances} = Appliance.list

    {can, defines} = Enum.reduce appliances, {[], []}, fn(appliance, {can, defines}) ->
      defines = case appliance.runtime do
        {:ref, refs} ->
          Enum.member?(refs, buildref) && [build | defines] || defines

        _ ->
          defines
      end

      matching = Dict.keys(appliance.builds.())
      can = if Enum.member? matching, buildref do
        [appliance | can]
      else
        can
      end

      {can, defines}
    end

    [
      appliances: [
        defined: defines,
        usable: can
      ]
    ]
  end
end
