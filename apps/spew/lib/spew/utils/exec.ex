defmodule Spew.Utils.Executable do
  @moduledoc """
  Helper utilities for executable files
  """

  @doc """
  Find dynamically linked libraries for a executable

  This is a simple wrapper around the unix tool `ldd` and is
  completely non-portable.

  If the file can be read AND the file is a dynamic executable it
  will return a list of files needed for it to run. If the file does
  not exist, is not readable, not executable, or any other error it
  will return a empty list, without notifying of any errors
  """
  @spec ldd(Path.t) :: [Path.t]
  def ldd(file), do: ldd2(file, [])
  defp ldd2(file, acc) do
    case System.cmd System.find_executable("ldd"),
                    [file],
                    [stderr_to_stdout: true] do
      {buf, 0} ->
        Enum.reduce String.split(buf, "\n"), acc, fn(line, acc) ->
          path = case String.split line, ~r/\s/, trim: true do
            [_name, "=>", path, _] ->
              path

            ["/" <> name = path, _] ->
              path

            _ ->
              nil
          end

          if nil !== path and ! Enum.member?(acc, path) do
            ldd2 path, [path | acc]
          else
            acc
          end
        end

      _ ->
        acc
    end
  end
end
