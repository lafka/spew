defmodule Spew.Mixfile do
  use Mix.Project

  def project do
    [
      app: :'spew-cli',
      version: "0.0.1",
      elixir: "~> 1.0",
      escript: escript,
      deps: []]
  end

  def escript do
    [
      main_module: SpewCLI,
      path: "bin/spew-cli",
      embed_elixir: true
    ]
  end

  def application do
    [
      applications: [ ]
    ]
  end
end
