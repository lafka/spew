defmodule Spewpanel.ApplianceView do
  use Spewpanel.Web, :view

  def buildinfo({nil, nil}), do: "No builds"
  def buildinfo({type, nil}), do: "#{type}, no spec"
  def buildinfo({"spew-archive-1.0", spec}), do:
    link("#{spec["TARGET"]}/#{spec["VSN"]}", to: "/build/#{spec["CHECKSUM"]}")
  def buildinfo({type, _spec}), do: "#{type}, unknown provider"
end
