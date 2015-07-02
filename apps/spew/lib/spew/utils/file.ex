defmodule Spew.Utils.File do
  @moduledoc """
  Common functions to work with files
  """

  @doc """
  Hash a file based on streaming API
  """
  def hash(type \\ :sha, file) do
    ctx = :crypto.hash_init type

    File.stream!(file, [], 2048)
      |> Enum.reduce(ctx, fn(buf, acc) ->
        :crypto.hash_update acc, buf
      end)
      |> :crypto.hash_final
      |> Base.encode16
      |> String.downcase
  end

  @doc """
  Check the GPG signature of a file

  ## Note

  There is no, or very little, support for GPG directly in Erlang.
  An external shell is therefore executed to verify the signature.
  This means that the trustdb of the running user is the one being
  checked against. All key management is therefore out of `spew`s
  scope. This will most likely change in future versions
  """
  def trusted?(file, signature) do
    gpg = System.find_executable("gpg")
    case System.cmd gpg, (case file do
                           nil -> ["--verify", signature]
                           file -> ["--verify",  signature, file]
                         end), [stderr_to_stdout: true] do

      {_, 0} ->
        :ok

      {_, 2} ->
        {:error, :unsigned}

      {_, 256} ->
        {:error, :signature}
    end
  end
end

