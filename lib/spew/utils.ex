defmodule Spew.Utils do
  def hashfile(type, file) do
    ctx = :crypto.hash_init type
    File.stream!(file, [], 2048)
      |> Enum.reduce(ctx, fn(buf, acc) ->
        :crypto.hash_update acc, buf
      end)
      |> :crypto.hash_final
      |> Base.encode16
      |> String.downcase
  end

  def gpgverify(sigfile, file \\ nil) do
    cmd = case file do
      nil ->
        '#{System.find_executable("gpg")} --verify #{sigfile}'

      file ->
        '#{System.find_executable("gpg")} --verify #{sigfile} #{file}'
    end

    case :exec.run cmd, [:sync, :stdout] do
      {:ok, []} ->
        :ok

      {:error, [exit_status: 256]} ->
        {:error, :signature}
    end
  end

  # merge a into b
  def deepmerge(%{} = a, %{} = b) do
    Map.merge norm(b), norm(a), fn
      (_k, b1, a1) when is_map(a) and is_map(b) ->
        deepmerge(b1, a1)

      # default to overwrite value if not map/list
      (_k, _b1, a1) ->
        a1
    end
  end
  def deepmerge(a, []), do: a
  def deepmerge(a, [{_,_} | _] = b) when is_list(a) do
    Dict.merge a, b, fn
      (_k, b1, a1) when is_list(a) and is_list(b) ->
        deepmerge a1, b1

      # default to overwrite value if not map/list
      (_k, _b1, a1) ->
        a1
    end
  end
  def deepmerge(_a, b), do: b

  defp norm(%{} = x), do: Map.delete(x, :__struct__)
  defp norm([]), do: %{}
  defp norm([{_,_}|_] = x), do: Enum.into(x, %{})


  defmodule Fs do
    def mounted?(target), do: mounted?(target, nil)
    def mounted?(target, source) do
      {buf, 0} = System.cmd System.find_executable("mount"), []
      case Regex.run ~r/(.*?)\son\s(#{target})/, buf do
        [_line, ^source, ^target] ->
            true

        [_line, _source, ^target] when source === nil ->
            true

        _ ->
          false
      end
    end

    def bindmount(source, target) do
      IO.puts 'sudo mount -o bind,ro "#{source}" "#{target}"'
      case :exec.run 'sudo mount -o bind,ro "#{source}" "#{target}"', [:sync, :stderr, :stdout] do
        {:ok, []} ->
          :ok

        {:error, err} ->
          {:error, err[:exit_status]}
      end
    end
  end
end
