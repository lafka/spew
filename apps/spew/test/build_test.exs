defmodule BuildTest do
  use ExUnit.Case

  alias Spew.Build
  alias Spew.Build.Server
  alias Spew.Build.Item


  defp testdir, do: Path.join(__DIR__, "builds")

  test "scan builds" do
    refs = Enum.map Path.wildcard(testdir <> "/**/*.tar"),
                    &Spew.Utils.File.hash(&1)

    {:ok, server} = Server.start_link name: __MODULE__,
                                      init: [pattern: "*/*",
                                             searchpath: [testdir],
                                             notify_reload?: true]

    {:ok, builds} = Build.list server
    for ref <- refs do
      assert Map.has_key?(builds, ref), "build #{ref} not found"
    end
  end

  test "add / get build" do
    {:ok, server} = Server.start_link name: __MODULE__,
                                      init: [pattern: "*/*",
                                             searchpath: []]

    {:ok, %Item{} = build} = Build.add  %Item{ref: Spew.Utils.hash("add-get"),
                                    name: "add-get",
                                    vsn: "test"}, node, server

    assert {:ok, build} == Build.get build.ref, server
  end

  test "list builds" do
    {:ok, server} = Server.start_link name: __MODULE__,
                                      init: [pattern: "*/*",
                                             searchpath: []]
    assert {:ok, %{}} == Build.list server


    {:ok, %Item{} = build1} = Build.add  %Item{ref: Spew.Utils.hash("list-1"),
                                    name: "list-1",
                                    vsn: "test"}, node, server
    {:ok, %Item{} = build2} = Build.add  %Item{ref: Spew.Utils.hash("list-2"),
                                    name: "list-2",
                                    vsn: "test"}, node, server

    # the result of the hash dictates sorting. be careful
    {:ok, builds} = Build.list server
    assert Enum.sort([{build1.ref, build1}, {build2.ref, build2}]) == Enum.sort(builds)
  end

  test "query builds" do
    {:ok, server} = Server.start_link name: __MODULE__,
                                      init: [pattern: "*/*",
                                             searchpath: []]
    assert {:ok, %{}} == Build.query "", true, server


    {:ok, %Item{} = build1} = Build.add  %Item{ref: Spew.Utils.hash("query-1"),
                                    name: "target-1",
                                    vsn: "test"}, node, server
    {:ok, %Item{} = build2} = Build.add  %Item{ref: Spew.Utils.hash("query-2"),
                                    name: "target-1",
                                    vsn: "test"}, node, server
    {:ok, %Item{} = build3} = Build.add  %Item{ref: Spew.Utils.hash("query-3"),
                                    name: "target-2",
                                    vsn: "test"}, node, server

    # get only the references
    assert {:ok, %{"target-1" => %{
                    "test" => Enum.sort([build1.ref, build2.ref])},
                   "target-2" => %{
                    "test" => [build3.ref]}}} == Build.query "", true, server

    # get the entire thing
    assert {:ok, %{"target-1" => %{
                    "test" => Enum.sort([build1, build2])},
                   "target-2" => %{
                    "test" => [build3]}}} == Build.query "", false, server

    # check that tree gets updated
    {:ok, %Item{} = build4} = Build.add  %Item{ref: Spew.Utils.hash("query-4"),
                                    name: "target-2",
                                    vsn: "sibling"}, node, server

    assert {:ok, %{"target-1" => %{
                    "test" => Enum.sort([build1.ref, build2.ref])},
                   "target-2" => %{
                    "test" => [build3.ref],
                    "sibling" => [build4.ref]}}} == Build.query "", true, server
  end

  test "unpack build" do
    {:ok, server} = Server.start_link name: __MODULE__,
                                      init: [pattern: "*/*",
                                             searchpath: [testdir],
                                             notify_reload?: true]

    # find archive-unsigned and archive-gpg-signed,
    # the first will fail to unpack as it's unsigned
    {:ok, builds} = Build.list server
    {_, gpgsignedbuild} = Enum.find builds, fn({_, %{vsn: vsn}}) -> vsn === "archive-gpg-signed" end
    {_, unsignedbuild} = Enum.find builds, fn({_, %{vsn: vsn}}) -> vsn === "archive-unsigned" end

    target = tmpdir

    on_exit fn ->
      File.rm_rf! target
    end

    {:ok, _newroot} = Item.unpack gpgsignedbuild, target
    {:ok, taredfiles} = :erl_tar.table gpgsignedbuild.spec["ARCHIVE"]
    taredfiles = Enum.map taredfiles, &("#{&1}")
    files = filetable target

    assert taredfiles == files

    assert {:error, {{:untrusted, :unsigned}, {:build, unsignedbuild.ref}}} == Item.unpack unsignedbuild, target
  end

  # @todo 2015-07-02 lafka; should be a test to validate checksum mismatch
  #                         ie. /something/ changed the build after it
  #                         was added. Also maybe there should be a
  #                         way to dictate the checksum to match
  #                         against in some kind of manifest...
  defp tmpdir do
    dir = :crypto.hash(:sha, "#{inspect Spew.Utils.Time.monotonic}")
      |> Base.encode16
      |> String.downcase
      |> String.slice 0, 7
    Path.join [System.tmp_dir, "spewtest", "build", dir]
  end

  defp filetable(cwd) do
    [cwd | Path.wildcard Path.join(cwd, "**")]
      |> Enum.map &(String.replace(&1, ~r/^#{cwd}\/?/, "./"))
  end
end
