defmodule RTFA.Mixfile do
  use Mix.Project

  def project do
    [
      app: :'rtfa-cli',
      version: "0.0.1",
      elixir: "~> 1.0",
      escript: escript,
      deps: []]
  end

  def escript do
    [
      main_module: RTFACLI,
      path: "bin/rtfa-cli",
      embed_elixir: true
    ]
  end

  def application do
    [
      applications: [ ]
    ]
  end
end
