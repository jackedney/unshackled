defmodule Unshackled.Embedding.Stagnation do
  @moduledoc """
  Stagnation detection for Cartographer activation.

  This module detects when the swarm is stuck in a local basin by analyzing
  trajectory movement in embedding space. Stagnation is triggered when
  movement remains below a threshold for 5+ consecutive cycles.

  Stagnation is defined as:
  - Trajectory movement below threshold for 5+ consecutive cycles
  - Movement measured as euclidean distance between consecutive embeddings
  - Large jumps reset the stagnation counter

  ## Example Usage

      iex> trajectory_points = [
      ...>   %{embedding_vector: Nx.tensor([1.0, 2.0])},
      ...>   %{embedding_vector: Nx.tensor([1.005, 2.005])},
      ...>   %{embedding_vector: Nx.tensor([1.003, 2.003])},
      ...>   %{embedding_vector: Nx.tensor([1.004, 2.004])},
      ...>   %{embedding_vector: Nx.tensor([1.002, 2.002])},
      ...>   %{embedding_vector: Nx.tensor([1.003, 2.003])},
      ...>   %{embedding_vector: Nx.tensor([1.004, 2.004])}
      ...> ]
      iex> {is_stagnant, cycles, avg} = Stagnation.detect_stagnation(trajectory_points, 0.01)
      iex> is_stagnant
      true

  """

  alias Unshackled.Embedding.Similarity

  @type trajectory_point :: %{embedding_vector: Nx.Tensor.t() | binary()}
  @type stagnation_result :: {boolean(), non_neg_integer(), float()}

  @doc """
  Detects stagnation based on trajectory movement.

  Returns {is_stagnant, cycles_stagnant, average_movement} where:
  - is_stagnant: boolean indicating if stagnation threshold is met
  - cycles_stagnant: number of consecutive cycles with movement below threshold
  - average_movement: average movement across all consecutive stagnant cycles

  ## Parameters

  - trajectory_points: List of trajectory points with embedding_vector field
  - threshold: Maximum euclidean distance to consider as stagnant

  ## Returns

  - {true, cycles_stagnant, average_movement} if stagnant for 5+ consecutive cycles
  - {false, cycles_stagnant, average_movement} if not stagnant

  ## Examples

      iex> trajectory = [
      ...>   %{embedding_vector: Nx.tensor([1.0, 2.0])},
      ...>   %{embedding_vector: Nx.tensor([1.005, 2.005])},
      ...>   %{embedding_vector: Nx.tensor([1.003, 2.003])},
      ...>   %{embedding_vector: Nx.tensor([1.004, 2.004])},
      ...>   %{embedding_vector: Nx.tensor([1.002, 2.002])},
      ...>   %{embedding_vector: Nx.tensor([1.003, 2.003])}
      ...> ]
      iex> {is_stagnant, cycles, avg} = Stagnation.detect_stagnation(trajectory, 0.01)
      iex> is_stagnant
      true
      iex> cycles
      5
      iex> is_number(avg)
      true

      iex> trajectory = [
      ...>   %{embedding_vector: Nx.tensor([1.0, 2.0])},
      ...>   %{embedding_vector: Nx.tensor([1.005, 2.005])},
      ...>   %{embedding_vector: Nx.tensor([1.003, 2.003])},
      ...>   %{embedding_vector: Nx.tensor([1.5, 2.5])}
      ...> ]
      iex> {is_stagnant, cycles, avg} = Stagnation.detect_stagnation(trajectory, 0.01)
      iex> is_stagnant
      false
      iex> cycles
      2

  """
  @spec detect_stagnation([trajectory_point()], float()) :: stagnation_result()
  def detect_stagnation(trajectory_points, threshold)
      when is_list(trajectory_points) and is_number(threshold) do
    if length(trajectory_points) < 2 do
      {false, 0, 0.0}
    else
      movements = calculate_movements(trajectory_points)
      analyze_stagnation(movements, threshold, 0, 0, [])
    end
  end

  def detect_stagnation(_, _) do
    {false, 0, 0.0}
  end

  @spec calculate_movements([trajectory_point()]) :: [float()]
  defp calculate_movements(trajectory_points) when length(trajectory_points) < 2 do
    []
  end

  defp calculate_movements(trajectory_points) do
    trajectory_points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [p1, p2] ->
      calculate_distance(p1, p2)
    end)
  end

  @spec calculate_distance(trajectory_point(), trajectory_point()) :: float()
  defp calculate_distance(p1, p2) do
    vec1 = decode_embedding(p1.embedding_vector)
    vec2 = decode_embedding(p2.embedding_vector)

    case Similarity.euclidean_distance(vec1, vec2) do
      {:ok, distance} -> distance
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  @spec decode_embedding(Nx.Tensor.t() | binary()) :: Nx.Tensor.t()
  defp decode_embedding(%Nx.Tensor{} = tensor), do: tensor

  defp decode_embedding(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary)
  rescue
    _ -> Nx.tensor([])
  end

  @spec analyze_stagnation([float()], float(), non_neg_integer(), non_neg_integer(), [float()]) ::
          stagnation_result()
  defp analyze_stagnation([], _threshold, consecutive_count, _total_count, stagnant_movements) do
    is_stagnant = consecutive_count >= 5
    average_movement = calculate_average(stagnant_movements)
    {is_stagnant, consecutive_count, average_movement}
  end

  defp analyze_stagnation(
         [movement | rest],
         threshold,
         consecutive_count,
         total_count,
         stagnant_movements
       ) do
    if movement < threshold do
      analyze_stagnation(rest, threshold, consecutive_count + 1, total_count + 1, [
        movement | stagnant_movements
      ])
    else
      analyze_stagnation(rest, threshold, 0, total_count + 1, [])
    end
  end

  @spec calculate_average([float()]) :: float()
  defp calculate_average([]), do: 0.0

  defp calculate_average(movements) do
    sum = Enum.sum(movements)
    count = length(movements)

    if count > 0 do
      sum / count
    else
      0.0
    end
  end
end
