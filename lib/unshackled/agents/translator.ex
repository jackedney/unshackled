defmodule Unshackled.Agents.Translator do
  @moduledoc """
  Translator agent that restates claims in different frameworks.

  The Translator agent takes a claim expressed in one domain and reinterprets
  it through the lens of another intellectual framework (physics, information
  theory, economics, biology, or mathematics). This cross-disciplinary
  translation often reveals hidden assumptions and clarifies the underlying
  structure of the claim.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server

  @framework_descriptions %{
    physics: """
    Physics: Translate the claim into concepts of energy, matter, forces,
    space, time, entropy, thermodynamics, quantum mechanics, relativity,
    conservation laws, fields, waves, particles, symmetry, and phase
    transitions. Focus on physical mechanisms, causal chains, and
    measurable quantities.
    """,
    information_theory: """
    Information Theory: Translate the claim into concepts of information,
    entropy as uncertainty, bits, encoding, decoding, noise, signal,
    bandwidth, compression, Shannon entropy, Kolmogorov complexity,
    mutual information, and information flow. Focus on the information
    content and communication aspects.
    """,
    economics: """
    Economics: Translate the claim into concepts of scarcity, utility,
    incentives, markets, supply, demand, equilibrium, tradeoffs, opportunity
    cost, marginal analysis, efficiency, externalities, and game theory.
    Focus on incentives, allocation mechanisms, and optimal decisions.
    """,
    biology: """
    Biology: Translate the claim into concepts of evolution, natural selection,
    fitness, adaptation, competition, cooperation, homeostasis, metabolism,
    reproduction, ecological niches, symbiosis, and evolutionary stable
    strategies. Focus on survival, reproduction, and adaptive dynamics.
    """,
    mathematics: """
    Mathematics: Translate the claim into formal structures, axioms, theorems,
    proofs, functions, sets, topology, geometry, calculus, algebra, logic,
    probability, statistics, and abstract relationships. Focus on formal
    representation and logical structure.
    """
  }

  @mere_rephrasing_patterns [
    "basically means",
    "essentially the same as",
    "is just another way of saying",
    "can be rephrased as",
    "is equivalent to stating",
    "similarly means"
  ]

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :translator
  def role, do: :translator

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to translate the current claim into a
  different framework, using the next available framework in the cycle.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{current_claim: claim, blackboard_name: bb_name}) do
    target_framework = determine_target_framework(bb_name)

    framework_description = Map.get(@framework_descriptions, String.to_atom(target_framework))

    """
    You are translating the following claim into the #{framework_name(target_framework)} framework.

    Current claim: #{claim}

    Framework description:
    #{framework_description}

    Your task:
    1. Identify the core structure and assumptions of the original claim
    2. Map these concepts to corresponding terms in the target framework
    3. Express the claim using the target framework's terminology and concepts
    4. Identify what hidden assumptions are revealed by this translation
    5. Ensure the translation is meaningful, not just a superficial rephrasing

    CRITICAL: The translation must reveal new insights, not merely rephrase
    - MEANINGFUL TRANSLATION: Reveals hidden assumptions, shows claim structure from a new perspective, exposes dependencies
    - MERE REPHRASING: "basically means," "is just another way of saying," surface-level synonym swapping

    FORBIDDEN patterns (any use invalidates your response):
    - "basically means" or "essentially the same as"
    - "is just another way of saying"
    - "can be rephrased as" without adding framework-specific insight
    - Superficial word swaps without conceptual mapping
    - Translation that could apply to any claim (framework-generic)

    Required response format (JSON):
    {
      "translated_claim": "The claim restated using the target framework's concepts",
      "target_framework": "#{target_framework}",
      "revealed_assumption": "Hidden assumption or structural feature revealed by this translation"
    }

    Example:
    If given: "Local thermodynamics allows entropy to decrease in isolated quantum systems"
    Translating to information theory:
    {
      "translated_claim": "In certain isolated quantum subsystems, information uncertainty can locally decrease when the subsystem is treated as an independent information source, suggesting that information entropy is not monotonically increasing at all scales of observation.",
      "target_framework": "information_theory",
      "revealed_assumption": "The original claim assumes that thermodynamic entropy and information entropy are fundamentally the same quantity, but the translation reveals that they may diverge when considering subsystem independence and information encoding mechanisms."
    }

    Another example:
    If given: "Markets tend toward equilibrium where supply equals demand"
    Translating to biology:
    {
      "translated_claim": "Populations tend toward stable ecological configurations where resource consumption by consumers matches resource production by the environment, with individual organisms evolving strategies that maximize fitness under these constraints.",
      "target_framework": "biology",
      "revealed_assumption": "The economic concept of equilibrium assumes a static balance state, whereas the biological translation reveals this as a dynamic evolutionary process with ongoing adaptation and population turnover, exposing the assumption that market participants have stable preferences."
    }

    Invalid response (mere rephrasing):
    {
      "translated_claim": "Local thermodynamics basically means that quantum systems can lower entropy locally.",
      "target_framework": "information_theory",
      "revealed_assumption": "..."
    }
    Error: This is a rephrasing, not a framework-specific translation

    Invalid response (framework-generic):
    {
      "translated_claim": "The claim suggests that systems can behave differently at small scales.",
      "target_framework": "information_theory",
      "revealed_assumption": "..."
    }
    Error: This could apply to any claim - no framework-specific insight

    Valid translation reveals assumptions like:
    - Physics → Economics: "Reveals assumption that rational choice is the primary driver, neglecting social and psychological factors"
    - Economics → Biology: "Shows assumption that preferences are fixed, unlike biological adaptation"
    - Information Theory → Physics: "Exposes assumption that all states are equally accessible, unlike energy landscapes"
    - Mathematics → Biology: "Highlights assumption of smoothness that breaks with discrete genetic mutations"

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts the translated claim, target framework,
  and revealed assumption.

  Returns a map with:
  - translated_claim: the claim restated in the target framework
  - target_framework: the framework used for translation
  - revealed_assumption: the hidden assumption or structural feature revealed
  - valid: boolean indicating if the response was properly formatted

  Invalid responses are flagged if:
  - Contains mere rephrasing patterns
  - Missing required fields
  - Malformed JSON
  - Framework-generic translation (could apply to any claim)
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "translated_claim" => translated_claim,
         "target_framework" => target_framework,
         "revealed_assumption" => revealed_assumption
       } = data} ->
        build_response_map(translated_claim, target_framework, revealed_assumption, data)

      {:ok, _partial} ->
        error_response(
          "Missing required fields: translated_claim, target_framework, and revealed_assumption"
        )

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(String.t(), String.t(), String.t(), map()) :: map()
  defp build_response_map(translated_claim, target_framework, revealed_assumption, _data) do
    base = %{
      translated_claim: translated_claim,
      target_framework: target_framework,
      revealed_assumption: revealed_assumption
    }

    cond do
      contains_mere_rephrasing?(translated_claim) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Translation contains mere rephrasing patterns instead of framework-specific insight"
        )

      not is_binary(translated_claim) or String.length(String.trim(translated_claim)) < 20 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "translated_claim must be a non-empty string with framework-specific content"
        )

      not is_binary(target_framework) or String.length(String.trim(target_framework)) < 3 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "target_framework must be a valid framework name")

      not valid_framework?(target_framework) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "target_framework must be one of: physics, information_theory, economics, biology, mathematics"
        )

      not is_binary(revealed_assumption) or String.length(String.trim(revealed_assumption)) < 20 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "revealed_assumption must be a non-empty string explaining what the translation reveals"
        )

      true ->
        Map.put(base, :valid, true)
    end
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      translated_claim: nil,
      target_framework: nil,
      revealed_assumption: nil,
      valid: false,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Translator agent.

  The Translator has no direct confidence impact (returns 0.0).
  The role is purely to provide cross-disciplinary perspective without affecting confidence.
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(%{valid: true}), do: 0.0

  def confidence_delta(%{valid: false}), do: 0.0

  @spec determine_target_framework(atom()) :: String.t()
  defp determine_target_framework(blackboard_name) do
    Server.get_next_translator_framework(blackboard_name)
  end

  @spec framework_name(String.t()) :: String.t()
  defp framework_name("physics"), do: "physics"
  defp framework_name("information_theory"), do: "information theory"
  defp framework_name("economics"), do: "economics"
  defp framework_name("biology"), do: "biology"
  defp framework_name("mathematics"), do: "mathematics"
  defp framework_name(_), do: "unknown"

  @spec contains_mere_rephrasing?(String.t()) :: boolean()
  defp contains_mere_rephrasing?(text) when is_binary(text) do
    lower_text = String.downcase(text)

    Enum.any?(@mere_rephrasing_patterns, fn pattern ->
      String.contains?(lower_text, pattern)
    end)
  end

  defp contains_mere_rephrasing?(_), do: false

  @spec valid_framework?(String.t()) :: boolean()
  defp valid_framework?(framework) do
    framework in ~w(physics information_theory economics biology mathematics)
  end
end
