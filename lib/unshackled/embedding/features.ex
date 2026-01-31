defmodule Unshackled.Embedding.Features do
  @moduledoc """
  Extracts structured features from claims for interpretable embedding dimensions.

  This module uses LLM calls to classify claims into structured categories:
  - claim_type: empirical (factual/observable), normative (ethical/should), causal (cause-effect)
  - quantification: universal (all/every), existential (some/exists), none (no quantifier)
  - modality: necessary (must/cannot), possible (may/can), actual (is/does)
  - domain: physics, philosophy, economics, biology, mathematics, information theory, etc

  Returns a feature vector as indices and optionally combines with semantic embedding.
  """

  alias Unshackled.LLM.Client

  @claim_types [:empirical, :normative, :causal]
  @quantifications [:universal, :existential, :none]
  @modalities [:necessary, :possible, :actual]
  @domains [
    :physics,
    :philosophy,
    :economics,
    :biology,
    :mathematics,
    :information_theory,
    :other
  ]

  @type claim_type :: :empirical | :normative | :causal
  @type quantification :: :universal | :existential | :none
  @type modality :: :necessary | :possible | :actual
  @type domain ::
          :physics
          | :philosophy
          | :economics
          | :biology
          | :mathematics
          | :information_theory
          | :other

  @type t :: %__MODULE__{
          claim_type: claim_type(),
          quantification: quantification(),
          modality: modality(),
          domain: domain()
        }

  defstruct [:claim_type, :quantification, :modality, :domain]

  @doc """
  Extracts structured features from claim text using LLM classification.

  ## Parameters

  - claim_text: The claim text to analyze

  ## Returns

  - {:ok, %Features{}} on successful classification
  - {:error, reason} on failure

  ## Examples

      iex> {:ok, features} = Features.extract_features("All entropy increases")
      iex> features.claim_type
      :empirical
      iex> features.quantification
      :universal
      iex> features.modality
      :necessary
      iex> features.domain
      :physics

      iex> Features.extract_features("")
      {:error, "Cannot extract features from empty string"}
  """
  @spec extract_features(String.t()) :: {:ok, t()} | {:error, String.t()}
  def extract_features(claim_text) when is_binary(claim_text) do
    trimmed = String.trim(claim_text)

    if trimmed == "" do
      {:error, "Cannot extract features from empty string"}
    else
      classify_claim(trimmed)
    end
  end

  def extract_features(_), do: {:error, "Invalid claim text type"}

  @doc """
  Converts feature struct to index vector [claim_type_idx, quantification_idx, modality_idx, domain_idx].
  Indices start at 0.
  """
  @spec to_vector(t()) :: [non_neg_integer()]
  def to_vector(%__MODULE__{} = features) do
    claim_type_idx = Enum.find_index(@claim_types, &(&1 == features.claim_type)) || 0
    quantification_idx = Enum.find_index(@quantifications, &(&1 == features.quantification)) || 0
    modality_idx = Enum.find_index(@modalities, &(&1 == features.modality)) || 0
    domain_idx = Enum.find_index(@domains, &(&1 == features.domain)) || 0

    [claim_type_idx, quantification_idx, modality_idx, domain_idx]
  end

  @doc """
  Combines structured features with semantic embedding into full embedding vector.

  ## Parameters

  - features: The feature struct
  - semantic_embedding: The Nx.Tensor semantic embedding (e.g., from Space.embed_claim)

  ## Returns

  - {:ok, Nx.Tensor.t()} combined embedding
  - {:error, reason} on failure

  The combined vector appends feature indices (normalized 0-1) to the semantic embedding.
  """
  @spec combine_with_semantic(t(), Nx.Tensor.t()) :: {:ok, Nx.Tensor.t()} | {:error, String.t()}
  def combine_with_semantic(%__MODULE__{} = features, %Nx.Tensor{} = semantic_embedding) do
    vector = to_vector(features)

    feature_tensor =
      vector
      |> Enum.map(fn idx -> idx / (length(vector) - 1) end)
      |> Nx.tensor(type: :f32)

    combined = Nx.concatenate([Nx.flatten(semantic_embedding), feature_tensor])

    {:ok, combined}
  end

  def combine_with_semantic(_, _) do
    {:error, "Invalid inputs to combine_with_semantic"}
  end

  @doc """
  Returns all possible values for each feature dimension.
  """
  @spec categories() :: %{
          claim_types: [claim_type()],
          quantifications: [quantification()],
          modalities: [modality()],
          domains: [domain()]
        }
  def categories do
    %{
      claim_types: @claim_types,
      quantifications: @quantifications,
      modalities: @modalities,
      domains: @domains
    }
  end

  defp classify_claim(claim_text) do
    prompt = build_classification_prompt(claim_text)

    messages = [
      %{
        role: "system",
        content: "You are a precise classifier that categorizes claims into structured types."
      },
      %{role: "user", content: prompt}
    ]

    case Client.chat_random(messages) do
      {:ok, response_struct, _model} ->
        parse_classification_response(response_struct.content)

      {:error, _reason} ->
        {:ok, default_features()}
    end
  rescue
    _ ->
      {:ok, default_features()}
  end

  defp build_classification_prompt(claim_text) do
    """
    Classify the following claim into structured categories.

    Claim: "#{claim_text}"

    Provide your answer as a JSON object with these exact keys:
    - claim_type: One of "empirical", "normative", or "causal"
      - empirical: factual claims about observable reality, what is
      - normative: ethical or prescriptive claims, what should be
      - causal: claims about cause-and-effect relationships

    - quantification: One of "universal", "existential", or "none"
      - universal: applies to all cases (all, every, always)
      - existential: applies to some cases (some, exists, sometimes)
      - none: no explicit quantifier

    - modality: One of "necessary", "possible", or "actual"
      - necessary: must, cannot, necessarily
      - possible: may, can, possibly
      - actual: is, does, actually

    - domain: One of "physics", "philosophy", "economics", "biology", "mathematics", "information_theory", or "other"

    Return ONLY the JSON object, no other text.
    """
  end

  defp parse_classification_response(response) do
    trimmed = String.trim(response)

    with {:ok, json} <- extract_json(trimmed),
         {:ok, data} <- Jason.decode(json),
         true <- is_map(data),
         claim_type when is_binary(claim_type) <- Map.get(data, "claim_type"),
         quantification when is_binary(quantification) <- Map.get(data, "quantification"),
         modality when is_binary(modality) <- Map.get(data, "modality"),
         domain when is_binary(domain) <- Map.get(data, "domain") do
      features = %__MODULE__{
        claim_type: normalize_claim_type(claim_type),
        quantification: normalize_quantification(quantification),
        modality: normalize_modality(modality),
        domain: normalize_domain(domain)
      }

      {:ok, features}
    else
      _ ->
        {:ok, default_features()}
    end
  end

  defp extract_json(text) do
    case Regex.run(~r/\{[^{}]*\}/, text) do
      [json | _] -> {:ok, json}
      nil -> {:error, "No JSON found"}
    end
  end

  defp normalize_claim_type(value) when is_binary(value) do
    normalized = String.downcase(value) |> String.replace(" ", "_")

    if normalized in ["empirical", "normative", "causal"] do
      String.to_atom(normalized)
    else
      :empirical
    end
  end

  defp normalize_quantification(value) when is_binary(value) do
    normalized = String.downcase(value) |> String.replace(" ", "_")

    if normalized in ["universal", "existential", "none"] do
      String.to_atom(normalized)
    else
      :none
    end
  end

  defp normalize_modality(value) when is_binary(value) do
    normalized = String.downcase(value) |> String.replace(" ", "_")

    if normalized in ["necessary", "possible", "actual"] do
      String.to_atom(normalized)
    else
      :actual
    end
  end

  defp normalize_domain(value) when is_binary(value) do
    normalized = String.downcase(value) |> String.replace(" ", "_")

    valid_domains = [
      "physics",
      "philosophy",
      "economics",
      "biology",
      "mathematics",
      "information_theory",
      "other"
    ]

    if normalized in valid_domains do
      String.to_atom(normalized)
    else
      :other
    end
  end

  defp default_features do
    %__MODULE__{
      claim_type: :empirical,
      quantification: :none,
      modality: :actual,
      domain: :other
    }
  end
end
