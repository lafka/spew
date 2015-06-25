defmodule Spewpanel.HostView do
  use Spewpanel.Web, :view

  def ip_to_string({mask,_}), do: ip_to_string(mask)
  def ip_to_string({a,b,c,d}), do: Enum.join([a,b,c,d], ".")
  def ip_to_string({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.join(":")
      |> String.downcase
  end
  def ip_to_string(ips) when is_list(ips), do: Enum.map(ips, &ip_to_string/1)
  def ip_to_string(x), do: inspect(IO.inspect(x))

  def mac_to_string(mac) do
    mac
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.join(":")
      |> String.downcase
  end

  def get_cidr({_, cidr}), do: "#{cidr}"

  def get_builds_tree(builds) do
    Spewbuild.tree builds
  end
end
