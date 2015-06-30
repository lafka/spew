defmodule SpewNetworkTest do
  use ExUnit.Case

  alias Spew.Network

  test "claim network slice" do
    # this test ONLY checks that we are repeatedly given the same
    # slice as long as the hostname stays the same. There is no check
    # to see if this is already claimed, or any functions to
    # statically assign networks

    assert {:ok, [{{172, 21, 26, 0}, 25},
                  {{64512, 16384, 4, 0, 20993, 51363, 16384, 0}, 100}]}
          == Network.netslice "spew", "break if hashfun or network cfg changes"
  end
end
