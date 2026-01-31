defmodule Unshackled.Costs.Extractor do
  @moduledoc """
  Extracts cost metadata from ExLLM LLM responses.

  This module handles extraction of token counts and cost information from
  ExLLM response structs, with graceful degradation when metadata is missing.

  ## ExLLM Response Structure

  ExLLM returns responses as `ExLLM.Types.LLMResponse` structs with the following
  relevant fields:

      %ExLLM.Types.LLMResponse{
        content: "response text",
        model: "openai/gpt-5.2",
        usage: %{
          input_tokens: 100,
          output_tokens: 50
        },
        cost: %{
          total_cost: 0.0015,
          input_cost: 0.0001,
          output_cost: 0.0014,
          currency: "USD"
        },
        finish_reason: "stop",
        id: "chatcmpl-xxx",
        ...
      }

  The `usage` field contains token counts and `cost` contains calculated costs.
  Both fields may be `nil` if the provider doesn't return usage data or
  if cost calculation is disabled.

  ## Examples

      iex> response = %ExLLM.Types.LLMResponse{
      ...>   content: "Hello",
      ...>   usage: %{input_tokens: 100, output_tokens: 50},
      ...>   cost: %{total_cost: 0.0015}
      ...> }
      iex> Extractor.extract_cost_data(response)
      {:ok, %{input_tokens: 100, output_tokens: 50, cost_usd: 0.0015}}

      iex> Extractor.extract_cost_data(nil)
      {:ok, %{input_tokens: 0, output_tokens: 0, cost_usd: 0.0}}

      iex> Extractor.extract_cost_data(%{content: "response"})
      {:ok, %{input_tokens: 0, output_tokens: 0, cost_usd: 0.0}}
  """

  @type cost_data :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cost_usd: float()
        }

  @type response :: ExLLM.Types.LLMResponse.t() | map() | nil

  @default_cost_data %{input_tokens: 0, output_tokens: 0, cost_usd: 0.0}

  @doc """
  Extracts cost data from an ExLLM response.

  Returns a tuple with cost data map containing input_tokens, output_tokens,
  and cost_usd. If any of these values are missing from the response, they
  default to 0 or 0.0 for graceful degradation.

  ## Parameters

  - `response`: An ExLLM response struct, map, or nil

  ## Returns

  - `{:ok, cost_data}` where cost_data is a map with:
    - `:input_tokens` - Integer count of input tokens (default 0)
    - `:output_tokens` - Integer count of output tokens (default 0)
    - `:cost_usd` - Float cost in USD (default 0.0)

  ## Examples

      iex> response = %ExLLM.Types.LLMResponse{
      ...>   usage: %{input_tokens: 100, output_tokens: 50},
      ...>   cost: %{total_cost: 0.0015}
      ...> }
      iex> Extractor.extract_cost_data(response)
      {:ok, %{input_tokens: 100, output_tokens: 50, cost_usd: 0.0015}}

      iex> Extractor.extract_cost_data(nil)
      {:ok, %{input_tokens: 0, output_tokens: 0, cost_usd: 0.0}}
  """
  @spec extract_cost_data(response()) :: {:ok, cost_data()}
  def extract_cost_data(nil), do: {:ok, @default_cost_data}

  def extract_cost_data(response) when is_map(response) do
    normalized = normalize_keys(response)

    cost_data = %{
      input_tokens: get_nested(normalized, [:usage, :input_tokens], 0) |> normalize_tokens(),
      output_tokens: get_nested(normalized, [:usage, :output_tokens], 0) |> normalize_tokens(),
      cost_usd: get_nested(normalized, [:cost, :total_cost], 0.0) |> normalize_cost()
    }

    {:ok, cost_data}
  end

  def extract_cost_data(_other), do: {:ok, @default_cost_data}

  # Normalizes string keys to atoms recursively for consistent access
  # Handles both plain maps and structs
  @spec normalize_keys(term()) :: term()
  defp normalize_keys(%{__struct__: _} = struct) do
    # Convert struct to map first, then normalize
    struct
    |> Map.from_struct()
    |> normalize_keys()
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        atom_key = safe_to_atom(key)
        {atom_key, normalize_keys(value)}

      {key, value} ->
        {key, normalize_keys(value)}
    end)
  end

  defp normalize_keys(value), do: value

  # Safely converts string to existing atom, or returns the string if atom doesn't exist
  @spec safe_to_atom(String.t()) :: atom() | String.t()
  defp safe_to_atom(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> string
  end

  # Gets a nested value from a map using a list of keys
  @spec get_nested(map(), [atom()], term()) :: term()
  defp get_nested(map, keys, default) do
    Enum.reduce_while(keys, map, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, default}
      end
    end)
  end

  @spec normalize_tokens(term()) :: non_neg_integer()
  defp normalize_tokens(tokens) when is_number(tokens), do: max(trunc(tokens), 0)
  defp normalize_tokens(_), do: 0

  @spec normalize_cost(term()) :: float()
  defp normalize_cost(cost) when is_number(cost), do: max(cost / 1, 0.0)
  defp normalize_cost(_), do: 0.0
end
