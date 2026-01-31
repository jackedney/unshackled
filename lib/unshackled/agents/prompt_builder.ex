defmodule Unshackled.Agents.PromptBuilder do
  @moduledoc """
  Shared utilities for building agent prompts and handling common patterns.

  Provides functions to:
  - Extract common context fields from Server struct
  - Validate minimum cycle requirements
  - Generate JSON instruction blocks for prompts
  - Build standardized error response maps
  """

  alias Unshackled.Blackboard.Server

  @doc """
  Extracts common Server fields into a map.

  Returns a map containing the most commonly used fields from Server struct
  for easy access in agent prompts and logic.

  ## Parameters
    - server: Server struct or nil

  ## Returns
    - Map of Server fields when server is provided
    - Empty map when server is nil

  ## Raises
    - ArgumentError when server is not a Server struct

  ## Examples

      iex> server = %Server{current_claim: "test", support_strength: 0.5, cycle_count: 5}
      iex> PromptBuilder.extract_context(server)
      %{current_claim: "test", support_strength: 0.5, cycle_count: 5}

      iex> PromptBuilder.extract_context(nil)
      %{}

  """
  @spec extract_context(Server.t() | nil) :: map()
  def extract_context(%Server{} = server) do
    %{
      current_claim: server.current_claim,
      support_strength: server.support_strength,
      cycle_count: server.cycle_count,
      blackboard_id: server.blackboard_id,
      blackboard_name: server.blackboard_name,
      active_objection: server.active_objection,
      analogy_of_record: server.analogy_of_record,
      frontier_pool: server.frontier_pool,
      cemetery: server.cemetery,
      graduated_claims: server.graduated_claims,
      embedding: server.embedding,
      translator_frameworks_used: server.translator_frameworks_used,
      cost_limit_usd: server.cost_limit_usd
    }
  end

  def extract_context(nil), do: %{}

  def extract_context(other) do
    raise ArgumentError, "Expected Server struct or nil, got: #{inspect(other)}"
  end

  @doc """
  Checks if the server has reached minimum cycle requirement.

  Used by agents that need a certain number of cycles before they
  can operate effectively (e.g., Cartographer needs 5 cycles
  for trajectory data).

  ## Parameters
    - server: Server struct
    - min_cycles: Minimum number of cycles required (non-negative integer)

  ## Returns
    - true if cycle_count >= min_cycles
    - false otherwise

  ## Examples

      iex> server = %Server{cycle_count: 5}
      iex> PromptBuilder.has_min_cycles?(server, 5)
      true

      iex> PromptBuilder.has_min_cycles?(server, 6)
      false

      iex> server = %Server{cycle_count: nil}
      iex> PromptBuilder.has_min_cycles?(server, 5)
      false

  """
  @spec has_min_cycles?(Server.t(), non_neg_integer()) :: boolean()
  def has_min_cycles?(%Server{cycle_count: cycle_count}, min_cycles)
      when is_integer(cycle_count) and is_integer(min_cycles) do
    cycle_count >= min_cycles
  end

  def has_min_cycles?(%Server{cycle_count: _}, _min_cycles), do: false

  def has_min_cycles?(server, min_cycles) do
    raise ArgumentError,
          "Expected Server struct with cycle_count, got: #{inspect(server)} with min_cycles: #{min_cycles}"
  end

  @doc """
  Builds a standard JSON response format block for prompts.

  Generates a formatted JSON template showing the required response structure,
  including field names, types, and descriptions.

  ## Parameters
    - fields: Map or keyword list of field definitions
      - Each field should be: {field_name, description} or %{field_name => description}

  ## Returns
    - Formatted string with JSON template

  ## Examples

      iex> fields = %{new_claim: "Your definitive extension of claim", inference_type: "deductive|inductive|abductive"}
      iex> PromptBuilder.json_instructions(fields)
      "Required response format (JSON)..."

  """
  @spec json_instructions(map() | keyword()) :: String.t()
  def json_instructions(fields) when is_map(fields) do
    field_strings =
      fields
      |> Enum.map(fn {key, description} ->
        ~s(  "#{key}": "#{description}")
      end)
      |> Enum.join(",\n")

    "Required response format (JSON)\n{\n#{field_strings}\n}"
  end

  def json_instructions(fields) when is_list(fields) do
    fields
    |> Map.new()
    |> json_instructions()
  end

  @doc """
  Builds a standardized error response map.

  Creates a map with all specified fields set to nil, plus
  valid: false and the provided error message.

  ## Parameters
    - fields: List of atom field names to include in the error response
    - message: Error message string

  ## Returns
    - Map with fields set to nil, valid: false, and error: message

  ## Examples

      iex> PromptBuilder.error_response([:new_claim, :reasoning], "Missing fields")
      %{new_claim: nil, reasoning: nil, valid: false, error: "Missing fields"}

      iex> PromptBuilder.error_response([:objection, :target_premise, :clarifying_question], "Invalid JSON")
      %{objection: nil, target_premise: nil, clarifying_question: nil, valid: false, error: "Invalid JSON"}

  """
  @spec error_response([atom()], String.t()) :: map()
  def error_response(fields, message) when is_list(fields) and is_binary(message) do
    base =
      fields
      |> Enum.map(fn field -> {field, nil} end)
      |> Map.new()

    Map.merge(base, %{
      valid: false,
      error: message
    })
  end

  def error_response(fields, message) do
    raise ArgumentError,
          "Expected field list (atoms) and error message (string), got fields: #{inspect(fields)}, message: #{inspect(message)}"
  end
end
