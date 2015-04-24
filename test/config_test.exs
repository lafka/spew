defmodule ConfigTest do
  use ExUnit.Case

  alias RTFA.Appliance.Config
  alias RTFA.Appliance.Config.Item

  setup do
    Application.put_env :rtfa, :appliance, config: "test/config/appliances.config"
    :ok = Config.unload :all
  end

  test "load config" do
    # don't crash everything on broken config

    assert :ok = Config.load "test/config/broken.config"
    assert :ok = Config.load Application.get_env(:rtfa, :appliance)[:config]
    {:ok, vals1} = Config.fetch

    assert :ok = Config.load "test/config/config-test-appliances.config"
    {:ok, vals2} = Config.fetch

    assert vals2 === Dict.merge vals1, vals2
  end

  test "unload configuration" do
    assert :ok = Config.load Application.get_env(:rtfa, :appliance)[:config]
    assert {:ok, [_file]} = Config.files
    :ok = Config.unload :all
    assert {:ok, []} = Config.files

    assert :ok = Config.load Application.get_env(:rtfa, :appliance)[:config]
    assert :ok = Config.load "test/config/config-test-appliances.config"
    {:ok, [file, file2]} = Config.files
    :ok = Config.unload file
    assert {:ok, [file2]} = Config.files
  end

  test "config reload rewrites old entries" do
    assert :ok = Config.load "test/config/config-test-appliances.config"
    {:ok, {cfgref, beast}} = Config.fetch "the beast"

    assert :ok = Config.load "test/config/config-test-appliances-patch.config"
    assert {:error, {:not_found, cfgref}} === Config.fetch cfgref
    {:ok, {_, newbeast}} = Config.fetch "the beast"
    assert newbeast !== beast
  end

  test "config reload keeps config for running appliances" do
      assert true
  end

  test "transient config" do
    {:ok, cfgref} = Config.store %Item{name: "test", type: :shell, appliance: ["/bin/bash", []]}
    {:ok, {^cfgref, vals}} = Config.fetch cfgref
    assert vals.name === "test"

    {:ok, newcfgref} = Config.store cfgref, %Item{name: "test", type: :shell, appliance: ["/bin/ls", []]}
    assert {:error, {:not_found, cfgref}} == Config.fetch cfgref
    {:ok, {^newcfgref, vals}} = Config.fetch newcfgref
    assert vals.appliance === ["/bin/ls", []]
  end
end
