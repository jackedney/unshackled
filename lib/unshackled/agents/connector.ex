defmodule Unshackled.Agents.Connector do
  @moduledoc """
  Connector agent that finds cross-domain analogies.

  The Connector agent identifies analogies from different domains
  that can illuminate the current claim and provide testable mappings.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Agents.PromptBuilder
  alias Unshackled.Agents.Responses.ConnectorSchema
  alias Unshackled.Blackboard.Server
  import Ecto.Changeset

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :connector
  def role, do: :connector

  @doc """
  Builds a prompt from current blackboard state.

  The prompt instructs the LLM to find a cross-domain analogy
  that is specific enough to test.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(server) do
    ctx = PromptBuilder.extract_context(server)
    claim = ctx.current_claim

    """
    You are finding a cross-domain analogy for the following claim.

    Current claim: #{claim}

    Your task:
    1. Identify a domain DIFFERENT from the claim's domain (e.g., physics → information theory, economics → biology).
    2. Find a specific phenomenon or principle in that domain that maps to the claim.
    3. Explain the mapping clearly and specifically.
    4. The analogy must be specific enough to test - no vague generalities.

    CRITICAL: The analogy must be SPECIFIC and TESTABLE
    - Valid: "This is like Shannon's entropy in information theory because both measure disorder"
    - Valid: "This is like market equilibrium in economics because both reach balance through opposing forces"
    - Invalid: "This is like many things in nature"
    - Invalid: "This is similar to various phenomena in science"

    #{PromptBuilder.json_instructions(%{analogy: "The specific analogy following the format 'This is like X because Y'", source_domain: "The domain you are drawing from (e.g., information theory, economics, biology)", mapping_explanation: "Detailed explanation of how the domains map and why to analogy holds"})}

    Examples:

    Thermodynamics claim → Information theory:
    {
      "analogy": "This is like Shannon's entropy in information theory because both quantify of uncertainty or disorder in a system",
      "source_domain": "information theory",
      "mapping_explanation": "Thermodynamic entropy and Shannon entropy both measure to number of possible microstates. Higher entropy means more possible configurations, whether in energy states or bits of information."
    }

    Economics claim → Biology:
    {
      "analogy": "This is like resource competition in ecosystems because both involve limited resources driving allocation",
      "source_domain": "biology/ecology",
      "mapping_explanation": "Market competition and ecological competition both involve agents competing for scarce resources. The dynamics of supply/demand parallel predator/prey population dynamics."
    }

    Invalid analogy (too vague):
    {
      "analogy": "This is like many things in nature",
      "source_domain": "nature",
      "mapping_explanation": "Many natural systems exhibit similar patterns"
    }

    Invalid analogy (same domain):
    {
      "analogy": "This is like another thermodynamics principle",
      "source_domain": "thermodynamics",
      "mapping_explanation": "Both are physics concepts"
    }

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and validates it against the Connector schema.

  Returns {:ok, %ConnectorSchema{}} on valid response.
  Returns {:error, changeset} on invalid response.
  """
  @impl true
  @spec parse_response(String.t()) :: {:ok, ConnectorSchema.t()} | {:error, Ecto.Changeset.t()}
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok, data} ->
        attrs = %{
          analogy: Map.get(data, "analogy"),
          source_domain: Map.get(data, "source_domain"),
          mapping_explanation: Map.get(data, "mapping_explanation")
        }

        schema = %ConnectorSchema{}
        changeset = ConnectorSchema.changeset(schema, attrs)

        if changeset.valid? do
          schema_with_data = apply_changes(changeset)
          {:ok, schema_with_data}
        else
          {:error, changeset}
        end

      {:error, _reason} ->
        schema = %ConnectorSchema{}
        changeset = ConnectorSchema.changeset(schema, %{})
        {:error, add_error(changeset, :json, "Invalid JSON format")}
    end
  end

  @doc """
  Returns the confidence delta for the Connector agent.

  The Connector suggests +0.05 confidence boost if its analogy
  is rated as apt and specific.
  """
  @impl true
  @spec confidence_delta({:ok, ConnectorSchema.t()} | {:error, Ecto.Changeset.t()}) :: float()
  def confidence_delta({:ok, _schema}), do: 0.05

  def confidence_delta({:error, _changeset}), do: 0.0
end
