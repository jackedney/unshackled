defmodule Unshackled.Agents.Agent do
  @moduledoc """
  Behaviour defining the interface for all agent types in Unshackled system.
  All agents implement this behaviour to ensure consistent patterns.
  """

  alias Unshackled.Blackboard.Server

  @doc """
  Decodes a JSON response, stripping markdown code fences if present.

  LLMs often wrap JSON in ```json ... ``` even when instructed to
  return raw JSON. This function handles both cases.
  """
  @spec decode_json_response(String.t()) :: {:ok, map()} | {:error, Jason.DecodeError.t()}
  def decode_json_response(response) do
    response
    |> String.trim()
    |> strip_markdown_fences()
    |> Jason.decode()
  end

  defp strip_markdown_fences(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*\n?/i, "")
    |> String.replace(~r/\n?```\s*$/i, "")
    |> String.trim()
  end

  @doc """
  Returns the agent's role as an atom.
  """
  @callback role() :: atom()

  @doc """
  Builds a prompt from the current blackboard state.
  Agents receive only the current state, not historical context.
  """
  @callback build_prompt(Server.t()) :: String.t()

  @doc """
  Parses the LLM response and returns a structured output.

  Can return either:
  - A map with :valid key (legacy format)
  - {:ok, struct} | {:error, changeset} (new Ecto schema format)
  """
  @callback parse_response(String.t()) ::
              map() | {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Returns the confidence delta this agent suggests.

  Supports both legacy map format and new Ecto schema format.
  """
  @callback confidence_delta(map() | {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}) ::
              float()

  @type agent_result :: {:ok, atom(), String.t(), map(), float()} | {:error, term()}
end
