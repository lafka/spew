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
end
