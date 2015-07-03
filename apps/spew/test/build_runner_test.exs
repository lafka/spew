defmodule SpewBuildRunnerTest do

    use ExUnit.Case

    # - Build should be packed out, sync style
    # - Running two builds should be isolated. No access to each others
    #   file system
    # - stopping will unmount everything, but keep build unpacked
    # - deleting build#1 should NOT delete the builds files
    # - deleting build#2 will remove all build files async

  test "build integration" do
  end

  
end
