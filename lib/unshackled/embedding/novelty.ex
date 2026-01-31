defmodule Unshackled.Embedding.Novelty do
  @moduledoc """
  Novelty bonus for exploration guidance.

  This module provides functions for:
  - Calculating novelty of a claim based on distance from trajectory history
  - Applying novelty bonus to confidence scores for exploration incentive
  - Normalizing novelty scores to 0.0-1.0 range

  Novelty is defined as the minimum Euclidean distance to any previously visited
  point in the embedding space. Claims far from explored territory receive a
  confidence bonus (max +0.05) to encourage exploration.

  ## Example

      iex> trajectory = [
      ...>   %{embedding_vector: Nx.tensor([1.0, 2.0])},
      ...>   %{embedding_vector: Nx.tensor([2.0, 3.0])}
      ...> ]
      iex> claim_embedding = Nx.tensor([10.0, 20.0])
      iex> {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      iex> is_float(novelty)
      true
      iex> novelty >= 0.0 and novelty <= 1.0
      true

  """

  alias Unshackled.Embedding.Similarity

  @type trajectory_point :: %{embedding_vector: Nx.Tensor.t() | binary()}
  @type trajectory :: [trajectory_point()]

  @max_novelty_bonus 0.05
  @default_space_diameter 10.0

  @doc """
  Calculates novelty score for a claim embedding relative to trajectory history.

  Novelty is the minimum Euclidean distance to any previously visited point,
  normalized to 0.0-1.0 range based on space diameter.

  ## Parameters

  - claim_embedding: Nx.Tensor embedding of the current claim
  - trajectory_history: List of trajectory points with embedding_vector field

  ## Returns

  - {:ok, novelty_score} on success, where score is 0.0-1.0
  - {:error, reason} on failure

  ## Examples

      iex> trajectory = [
      ...>   %{embedding_vector: Nx.tensor([1.0, 2.0])},
      ...>   %{embedding_vector: Nx.tensor([2.0, 3.0])}
      ...> ]
      iex> claim_embedding = Nx.tensor([5.0, 6.0])
      iex> {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      iex> novelty >= 0.0 and novelty <= 1.0
      true

      iex> trajectory = []
      iex> claim_embedding = Nx.tensor([1.0, 2.0])
      iex> {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      iex> novelty
      1.0

  """
  @spec calculate_novelty(Nx.Tensor.t(), trajectory()) :: {:ok, float()} | {:error, String.t()}
  def calculate_novelty(%Nx.Tensor{} = claim_embedding, trajectory_history)
      when is_list(trajectory_history) do
    case calculate_min_distance(claim_embedding, trajectory_history) do
      {:ok, min_distance} ->
        normalize_novelty(min_distance)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def calculate_novelty(%Nx.Tensor{}, _) do
    {:error, "trajectory_history must be a list"}
  end

  def calculate_novelty(_, _) do
    {:error, "claim_embedding must be Nx.Tensor"}
  end

  @doc """
  Applies novelty bonus to base confidence.

  Returns confidence boost proportional to novelty score, capped at +0.05.

  ## Parameters

  - novelty_score: Novelty score between 0.0 and 1.0
  - base_confidence: Base confidence score (typically 0.0-1.0)

  ## Returns

  - {:ok, boosted_confidence} on success
  - {:error, reason} on failure

  ## Examples

      iex> {:ok, boosted} = Novelty.apply_novelty_bonus(1.0, 0.5)
      iex> boosted
      0.55

      iex> {:ok, boosted} = Novelty.apply_novelty_bonus(0.0, 0.5)
      iex> boosted
      0.5

  """
  @spec apply_novelty_bonus(float(), float()) :: {:ok, float()} | {:error, String.t()}
  def apply_novelty_bonus(novelty_score, base_confidence)
      when is_number(novelty_score) and is_number(base_confidence) do
    clamped_novelty = max(0.0, min(novelty_score, 1.0))
    bonus = clamped_novelty * @max_novelty_bonus
    boosted = base_confidence + bonus
    {:ok, boosted}
  end

  def apply_novelty_bonus(novelty_score, _) when is_number(novelty_score) do
    {:error, "base_confidence must be a number"}
  end

  def apply_novelty_bonus(_, base_confidence) when is_number(base_confidence) do
    {:error, "novelty_score must be a number"}
  end

  def apply_novelty_bonus(_, _) do
    {:error, "Both inputs must be numbers"}
  end

  @spec calculate_min_distance(Nx.Tensor.t(), trajectory()) ::
          {:ok, float() | :infinity} | {:error, String.t()}
  defp calculate_min_distance(claim_embedding, trajectory_history) do
    if length(trajectory_history) == 0 do
      {:ok, :infinity}
    else
      result =
        trajectory_history
        |> Enum.map(fn point ->
          point_embedding = decode_embedding(point.embedding_vector)
          Similarity.euclidean_distance(claim_embedding, point_embedding)
        end)
        |> Enum.filter(fn result -> match?({:ok, _}, result) end)
        |> Enum.map(fn {:ok, dist} -> dist end)
        |> Enum.min(fn -> :infinity end)

      {:ok, result}
    end
  rescue
    _ -> {:error, "Failed to calculate minimum distance"}
  end

  @spec normalize_novelty(float()) :: {:ok, float()}
  defp normalize_novelty(min_distance) do
    space_diameter = @default_space_diameter

    novelty =
      case min_distance do
        :infinity ->
          1.0

        dist when is_float(dist) or is_integer(dist) ->
          normalized = dist / space_diameter
          min(normalized, 1.0)

        _ ->
          0.0
      end

    {:ok, novelty}
  end

  @spec decode_embedding(Nx.Tensor.t() | binary()) :: Nx.Tensor.t()
  defp decode_embedding(%Nx.Tensor{} = tensor), do: tensor

  defp decode_embedding(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary)
  rescue
    _ -> Nx.tensor([])
  end

  defp decode_embedding(_), do: Nx.tensor([])
end
