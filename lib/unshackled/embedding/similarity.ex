defmodule Unshackled.Embedding.Similarity do
  @moduledoc """
  Similarity and distance functions for comparing embeddings.

  This module provides functions for:
  - Cosine similarity between vectors
  - Euclidean distance between vectors
  - Finding k nearest neighbors
  - Computing trajectory distance using Dynamic Time Warping (DTW)

  All functions work with Nx.Tensor representations of embeddings.
  """

  @type vector :: Nx.Tensor.t()
  @type trajectory :: [TrajectoryPoint.t()]
  @type neighbor :: {distance :: float(), TrajectoryPoint.t()}

  alias Unshackled.Embedding.TrajectoryPoint

  @doc """
  Computes cosine similarity between two vectors.

  Cosine similarity measures cosine of angle between two vectors,
  returning 1.0 for identical vectors, 0.0 for orthogonal vectors, and -1.0 for opposite vectors.

  ## Parameters

  - vec1: First Nx.Tensor vector
  - vec2: Second Nx.Tensor vector

  ## Returns

  - {:ok, similarity_score} on success, where score is a float between -1.0 and 1.0
  - {:error, reason} on failure

  ## Examples

      iex> vec = Nx.tensor([1.0, 2.0, 3.0])
      iex> {:ok, sim} = Similarity.cosine_similarity(vec, vec)
      iex> Float.round(sim, 6)
      1.0

      iex> vec1 = Nx.tensor([1.0, 0.0])
      iex> vec2 = Nx.tensor([0.0, 1.0])
      iex> {:ok, sim} = Similarity.cosine_similarity(vec1, vec2)
      iex> Float.round(sim, 6)
      0.0

  """
  @spec cosine_similarity(Nx.Tensor.t(), Nx.Tensor.t()) :: {:ok, float()} | {:error, String.t()}
  def cosine_similarity(vec1, vec2)

  def cosine_similarity(%Nx.Tensor{} = vec1, %Nx.Tensor{} = vec2) do
    {shape1, shape2} = {Nx.shape(vec1), Nx.shape(vec2)}

    cond do
      shape1 != shape2 ->
        {:error,
         "Vectors must have same dimensions, got #{inspect(shape1)} and #{inspect(shape2)}"}

      true ->
        dot_product = Nx.sum(Nx.multiply(vec1, vec2))

        norm1 = Nx.sqrt(Nx.sum(Nx.multiply(vec1, vec1)))
        norm2 = Nx.sqrt(Nx.sum(Nx.multiply(vec2, vec2)))

        similarity =
          Nx.divide(dot_product, Nx.multiply(norm1, norm2))
          |> Nx.to_number()

        {:ok, similarity}
    end
  end

  def cosine_similarity(_, _) do
    {:error, "Both inputs must be Nx.Tensor"}
  end

  @doc """
  Computes Euclidean distance between two vectors.

  Euclidean distance is straight-line distance between two points in vector space.

  ## Parameters

  - vec1: First Nx.Tensor vector
  - vec2: Second Nx.Tensor vector

  ## Returns

  - {:ok, distance} on success, where distance is a non-negative float
  - {:error, reason} on failure

  ## Examples

      iex> vec1 = Nx.tensor([1.0, 2.0, 3.0])
      iex> vec2 = Nx.tensor([4.0, 5.0, 6.0])
      iex> {:ok, dist} = Similarity.euclidean_distance(vec1, vec2)
      iex> Float.round(dist, 6)
      5.196152

  """
  @spec euclidean_distance(Nx.Tensor.t(), Nx.Tensor.t()) :: {:ok, float()} | {:error, String.t()}
  def euclidean_distance(vec1, vec2)

  def euclidean_distance(%Nx.Tensor{} = vec1, %Nx.Tensor{} = vec2) do
    {shape1, shape2} = {Nx.shape(vec1), Nx.shape(vec2)}

    cond do
      shape1 != shape2 ->
        {:error,
         "Vectors must have same dimensions, got #{inspect(shape1)} and #{inspect(shape2)}"}

      true ->
        diff = Nx.subtract(vec1, vec2)
        squared = Nx.multiply(diff, diff)
        sum_squared = Nx.sum(squared)

        distance = Nx.sqrt(sum_squared) |> Nx.to_number()

        {:ok, distance}
    end
  end

  def euclidean_distance(_, _) do
    {:error, "Both inputs must be Nx.Tensor"}
  end

  @doc """
  Finds k nearest neighbors to a query vector from a list of trajectory points.

  Uses Euclidean distance to find k closest points.

  ## Parameters

  - query: Nx.Tensor query vector
  - points: List of TrajectoryPoint structs
  - k: Number of nearest neighbors to find

  ## Returns

  - {:ok, [{distance, point}, ...]} on success, sorted by distance ascending
  - {:error, reason} on failure

  ## Examples

      iex> query = Nx.tensor([0.5, 0.5])
      iex> points = [
      ...>   %TrajectoryPoint{embedding_vector: Nx.tensor([0.1, 0.1]), claim_text: "far"},
      ...>   %TrajectoryPoint{embedding_vector: Nx.tensor([0.6, 0.6]), claim_text: "close"}
      ...> ]
      iex> {:ok, neighbors} = Similarity.nearest_neighbors(query, points, 2)
      iex> length(neighbors)
      2

  """
  @spec nearest_neighbors(Nx.Tensor.t(), [TrajectoryPoint.t()], non_neg_integer()) ::
          {:ok, [neighbor()]} | {:error, String.t()}
  def nearest_neighbors(%Nx.Tensor{} = query, points, k)
      when is_list(points) and is_integer(k) and k > 0 do
    if length(points) == 0 do
      {:ok, []}
    else
      result =
        points
        |> Enum.map(fn point ->
          with {:ok, embedding} <- decode_embedding(point),
               {:ok, distance} <- euclidean_distance(query, embedding) do
            {distance, point}
          else
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(fn {d1, _}, {d2, _} -> d1 <= d2 end)
        |> Enum.take(k)

      {:ok, result}
    end
  end

  def nearest_neighbors(%Nx.Tensor{}, _, k) when is_integer(k) and k <= 0 do
    {:error, "k must be positive integer, got #{k}"}
  end

  def nearest_neighbors(%Nx.Tensor{}, _, _) do
    {:error, "points must be a list"}
  end

  def nearest_neighbors(_, _, _) do
    {:error, "query must be Nx.Tensor"}
  end

  @doc """
  Computes trajectory distance between two trajectory sequences using Dynamic Time Warping (DTW).

  DTW finds the optimal alignment between two sequences by allowing non-linear mapping.
  Returns the minimum cumulative distance between aligned points.

  ## Parameters

  - trajectory1: First trajectory as list of TrajectoryPoint structs
  - trajectory2: Second trajectory as list of TrajectoryPoint structs

  ## Returns

  - {:ok, dtw_distance} on success
  - {:error, reason} on failure

  ## Examples

      iex> traj1 = [
      ...>   %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 2.0])},
      ...>   %TrajectoryPoint{embedding_vector: Nx.tensor([2.0, 3.0])}
      ...> ]
      iex> traj2 = [
      ...>   %TrajectoryPoint{embedding_vector: Nx.tensor([1.5, 2.5])},
      ...>   %TrajectoryPoint{embedding_vector: Nx.tensor([2.5, 3.5])}
      ...> ]
      iex> {:ok, dist} = Similarity.trajectory_distance(traj1, traj2)
      iex> is_float(dist)
      true

  """
  @spec trajectory_distance(trajectory(), trajectory()) :: {:ok, float()} | {:error, String.t()}
  def trajectory_distance(trajectory1, trajectory2)

  def trajectory_distance([], []) do
    {:ok, 0.0}
  end

  def trajectory_distance(traj1, traj2) when is_list(traj1) and is_list(traj2) do
    if length(traj1) == 0 or length(traj2) == 0 do
      {:ok, 0.0}
    else
      case decode_trajectory_embeddings(traj1, traj2) do
        {:ok, vectors1, vectors2} ->
          {:ok, compute_dtw(vectors1, vectors2)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def trajectory_distance(_, _) do
    {:error, "Both trajectories must be lists"}
  end

  @spec decode_trajectory_embeddings([TrajectoryPoint.t()], [TrajectoryPoint.t()]) ::
          {:ok, [Nx.Tensor.t()], [Nx.Tensor.t()]} | {:error, String.t()}
  defp decode_trajectory_embeddings(traj1, traj2) do
    decoded1 = Enum.map(traj1, &decode_embedding/1)
    decoded2 = Enum.map(traj2, &decode_embedding/1)

    errors1 = Enum.filter(decoded1, &(elem(&1, 0) == :error))
    errors2 = Enum.filter(decoded2, &(elem(&1, 0) == :error))

    if length(errors1) > 0 or length(errors2) > 0 do
      {:error, "Failed to decode embedding(s) in trajectory"}
    else
      vectors1 = Enum.map(decoded1, &elem(&1, 1))
      vectors2 = Enum.map(decoded2, &elem(&1, 1))
      {:ok, vectors1, vectors2}
    end
  end

  @spec compute_dtw([Nx.Tensor.t()], [Nx.Tensor.t()]) :: float()
  defp compute_dtw(vectors1, vectors2) do
    n = length(vectors1)
    m = length(vectors2)

    dtw_matrix =
      build_dtw_matrix(vectors1, vectors2, n, m)

    row = Enum.at(dtw_matrix, n, [])
    {_, val} = Enum.at(row, m, {0, 0.0})
    val
  end

  @spec build_dtw_matrix([Nx.Tensor.t()], [Nx.Tensor.t()], non_neg_integer(), non_neg_integer()) ::
          [{non_neg_integer(), float()}]
  defp build_dtw_matrix(vectors1, vectors2, n, m) do
    initial_row = List.duplicate({0, :infinity}, m + 1)
    initial_matrix = List.duplicate(initial_row, n + 1)

    initial_matrix
    |> update_matrix_cell(0, 0, {0, 0.0})
    |> fill_dtw_matrix(vectors1, vectors2, 1, n, 1, m)
  end

  @spec update_matrix_cell(
          [[{non_neg_integer(), float()}]],
          non_neg_integer(),
          non_neg_integer(),
          {non_neg_integer(), float()}
        ) ::
          [[{non_neg_integer(), float()}]]
  defp update_matrix_cell(matrix, row, col, value) do
    List.replace_at(matrix, row, List.replace_at(Enum.at(matrix, row), col, value))
  end

  @spec fill_dtw_matrix(
          [[{non_neg_integer(), float()}]],
          [Nx.Tensor.t()],
          [Nx.Tensor.t()],
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          [[{non_neg_integer(), float()}]]
  defp fill_dtw_matrix(matrix, _vectors1, _vectors2, i, n, _j, _m) when i > n do
    matrix
  end

  defp fill_dtw_matrix(matrix, vectors1, vectors2, i, n, j, m) when j > m do
    fill_dtw_matrix(matrix, vectors1, vectors2, i + 1, n, 1, m)
  end

  defp fill_dtw_matrix(matrix, vectors1, vectors2, i, n, j, m) do
    vec1 = Enum.at(vectors1, i - 1)
    vec2 = Enum.at(vectors2, j - 1)

    point_dist = euclidean_distance!(vec1, vec2)

    cost =
      min(
        get_cell(matrix, i - 1, j),
        min(get_cell(matrix, i, j - 1), get_cell(matrix, i - 1, j - 1))
      ) + point_dist

    new_matrix = update_matrix_cell(matrix, i, j, {0, cost})
    fill_dtw_matrix(new_matrix, vectors1, vectors2, i, n, j + 1, m)
  end

  @spec get_cell([[{non_neg_integer(), float()}]], non_neg_integer(), non_neg_integer()) ::
          float()
  defp get_cell(matrix, i, j) do
    matrix
    |> Enum.at(i, [])
    |> Enum.at(j, [])
    |> case do
      {_, val} when is_float(val) -> val
      _ -> :infinity
    end
  end

  @spec decode_embedding(TrajectoryPoint.t()) :: {:ok, Nx.Tensor.t()} | {:error, String.t()}
  defp decode_embedding(%TrajectoryPoint{embedding_vector: embedding})
       when is_binary(embedding) do
    try do
      tensor = :erlang.binary_to_term(embedding)
      {:ok, tensor}
    rescue
      _ -> {:error, "Failed to decode embedding binary"}
    end
  end

  defp decode_embedding(%TrajectoryPoint{embedding_vector: %Nx.Tensor{} = embedding}) do
    {:ok, embedding}
  end

  defp decode_embedding(_) do
    {:error, "Invalid embedding format"}
  end

  @spec euclidean_distance!(Nx.Tensor.t(), Nx.Tensor.t()) :: float()
  defp euclidean_distance!(vec1, vec2) do
    case euclidean_distance(vec1, vec2) do
      {:ok, distance} -> distance
      _ -> :infinity
    end
  end
end
