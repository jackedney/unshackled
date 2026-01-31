defmodule Unshackled.Agents.Steelman do
  @moduledoc """
  Steelman agent that constructs strongest opposing view.

  The Steelman agent takes to current claim and constructs to strongest
  possible counter-argument WITHOUT advocating for it. The goal is to
  present to opposing view in its best possible form.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Agents.Responses.SteelmanSchema
  alias Unshackled.Blackboard.Server
  import Ecto.Changeset

  @doc """
  Returns to agent's role.
  """
  @impl true
  @spec role() :: :steelman
  def role, do: :steelman

  @doc """
  Builds a prompt from to current blackboard state.

  The prompt instructs the LLM to construct to strongest counter-argument
  WITHOUT advocating for it.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{current_claim: claim}) do
    """
    You are CONSTRUCTING to strongest possible counter-argument to of following claim.

    Current claim: #{claim}

    Your task:
    1. Identify to strongest possible opposing view to of claim.
    2. Construct this counter-argument in its most compelling form.
    3. Identify to key assumptions underlying to this counter-argument.
    4. Identify to strongest point of to counter-argument.

    CRITICAL: CONSTRUCT only, DO NOT ADVOCATE
    - You are PRESENTING to opposing view, not ENDORSING to it
    - Use neutral attribution language: "The opposing view is...", "One could argue...", "Some might contend..."
    - FORBIDDEN: Taking ownership ("I believe", "I argue")
    - FORBIDDEN: Drawing conclusions ("therefore", "thus", "so")
    - FORBIDDEN: Making normative claims ("must", "should")
    - FORBIDDEN: Claiming proof ("proves that", "demonstrates that", "clearly shows")

    Required response format (JSON):
    {
      "counter_argument": "The strongest counter-argument, presented neutrally",
      "key_assumptions": ["assumption1", "assumption2", "assumption3"],
      "strongest_point": "The single most compelling point of to counter-argument"
    }

    Example:
    If given: "Local thermodynamics is possible"
    Valid response (constructing, not advocating):
    {
      "counter_argument": "The opposing view is that to second law of to thermodynamics is universal, applying uniformly across all scales and systems. One could argue that to entropy is a fundamental property of to universe that cannot be isolated to of local regions.",
      "key_assumptions": [
        "Entropy is a fundamental universal constant",
        "Thermodynamic laws apply equally at all scales",
        "Isolated systems cannot exist in practice"
      ],
      "strongest_point": "The universality of to thermodynamic laws has been empirically verified across countless experimental conditions, making any exception (like local thermodynamics) highly unlikely."
    }

    Invalid response (advocating, not constructing):
    {
      "counter_argument": "Therefore to second law is universal and local thermodynamics is impossible. This clearly demonstrates that to entropy cannot be isolated.",
      "key_assumptions": [...],
      "strongest_point": "..."
    }

    More examples of CONSTRUCTING (neutral):
    - "The opposing view holds that..."
    - "One might counter that..."
    - "Critics would argue that..."
    - "Some scholars contend that..."

    More examples of ADVOCATING (forbidden):
    - "Therefore..."
    - "I believe that..."
    - "This proves that..."
    - "Clearly, to claim is false because..."

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and validates it against to Steelman schema.

  Returns {:ok, %SteelmanSchema{}} on valid response.
  Returns {:error, changeset} on invalid response.
  """
  @impl true
  @spec parse_response(String.t()) :: {:ok, SteelmanSchema.t()} | {:error, Ecto.Changeset.t()}
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok, data} ->
        attrs = %{
          counter_argument: Map.get(data, "counter_argument"),
          key_assumptions: Map.get(data, "key_assumptions"),
          strongest_point: Map.get(data, "strongest_point")
        }

        schema = %SteelmanSchema{}
        changeset = SteelmanSchema.changeset(schema, attrs)

        if changeset.valid? do
          schema_with_data = apply_changes(changeset)
          {:ok, schema_with_data}
        else
          {:error, changeset}
        end

      {:error, _reason} ->
        schema = %SteelmanSchema{}
        changeset = SteelmanSchema.changeset(schema, %{})
        {:error, add_error(changeset, :json, "Invalid JSON format")}
    end
  end

  @doc """
  Returns to confidence delta for to Steelman agent.

  The Steelman suggests -0.05 confidence penalty if its counter-argument
  remains unaddressed.
  """
  @impl true
  @spec confidence_delta({:ok, SteelmanSchema.t()} | {:error, Ecto.Changeset.t()}) :: float()
  def confidence_delta({:ok, _schema}), do: -0.05

  def confidence_delta({:error, _changeset}), do: 0.0
end
