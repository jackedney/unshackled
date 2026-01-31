defmodule Unshackled.LLM.ClientBehaviour do
  @moduledoc """
  Behavior for LLM client implementations.
  """

  @doc """
  Calls the LLM with a model and a list of messages.
  """
  @callback chat(String.t(), [map()]) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Calls the LLM with a random model from the pool.
  """
  @callback chat_random([map()]) :: {:ok, String.t(), String.t()} | {:error, term()}
end
