defmodule Spew.Runner do

  use Behaviour

  @typep capability :: atom
  @typep signal :: String.t | non_neg_integer
  @typep opts :: [any]

  defcallback capabilitites :: [capability]
  defcallback supported? :: boolean
  defcallback run(Spew.Instance.Item.t, opts) :: {:ok, Spew.Instance.Item.t} | {:error, term}
  defcallback stop(Spew.Instance.Item.t, signal) :: {:ok, Spew.Instance.Item.t} | {:error, term}
  defcallback kill(Spew.Instance.Item.t) :: {:ok, Spew.Instance.Item.t} | {:error, term}

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end
end
