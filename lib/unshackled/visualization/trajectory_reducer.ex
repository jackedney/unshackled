defmodule Unshackled.Visualization.TrajectoryReducer do
  @moduledoc """
  Dimensionality reduction for trajectory visualization.

  Reduces high-dimensional embeddings (384 or 768 dims) to 3D coordinates
  for visualization using PCA followed by t-SNE.

  Uses ETS-based caching to avoid recomputing t-SNE on every request.
  Cache is keyed by blackboard_id and point count.
  """

  require Logger

  @ets_table :trajectory_reducer_cache
  @pca_intermediate_dim 64
  @tsne_output_dim 3
  @tsne_perplexity 5.0
  @tsne_learning_rate 200.0
  # Reduced from 300 to 100 for ~3x speedup with minimal quality loss
  @tsne_iterations 100
  # Minimum points to use t-SNE (below this, use PCA only - much faster)
  @tsne_min_points 10

  @doc """
  Ensures the ETS cache table exists. Called during application startup.
  """
  @spec ensure_cache_table() :: :ok
  def ensure_cache_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Reduces a list of high-dimensional embeddings to 3D coordinates.

  ## Parameters

  - embeddings: List of Nx.Tensor embeddings (384 or 768 dims)
  - blackboard_id: ID for cache lookup

  ## Returns

  List of {x, y, z} tuples

  ## Pipeline

  1. Normalize dimensions (pad 384-dim to match, or handle 768-dim legacy)
  2. PCA: reduce to 64 dimensions
  3. t-SNE: reduce 64 dimensions to 3D
  """
  @spec reduce_to_3d([Nx.Tensor.t()], integer()) :: [{float(), float(), float()}]
  def reduce_to_3d([], _blackboard_id), do: []

  def reduce_to_3d([_single], _blackboard_id) do
    # Single point - return origin
    [{0.0, 0.0, 0.0}]
  end

  def reduce_to_3d(embeddings, _blackboard_id) when length(embeddings) < 3 do
    # Less than 3 points - use simple projection
    simple_projection(embeddings)
  end

  def reduce_to_3d(embeddings, blackboard_id) do
    ensure_cache_table()
    point_count = length(embeddings)
    cache_key = {blackboard_id, point_count}

    case :ets.lookup(@ets_table, cache_key) do
      [{^cache_key, cached_coords}] ->
        cached_coords

      [] ->
        # Try incremental update first (reuse existing coordinates)
        coords = try_incremental_update(embeddings, blackboard_id, point_count)
        :ets.insert(@ets_table, {cache_key, coords})
        coords
    end
  end

  # Try to incrementally update by reusing coordinates from previous point count
  defp try_incremental_update(embeddings, blackboard_id, point_count) do
    # Look for cached coordinates with one fewer point
    prev_cache_key = {blackboard_id, point_count - 1}

    case :ets.lookup(@ets_table, prev_cache_key) do
      [{^prev_cache_key, prev_coords}] when length(prev_coords) == point_count - 1 ->
        # We have coordinates for all but the last point - compute incrementally
        compute_incremental(embeddings, prev_coords)

      _ ->
        # No previous cache or mismatch - full recomputation
        compute_reduction(embeddings)
    end
  end

  # Compute coordinates for a single new point while preserving existing positions
  defp compute_incremental(embeddings, prev_coords) do
    try do
      # Get the new embedding (last one)
      new_embedding = List.last(embeddings)
      new_flat = Nx.flatten(new_embedding)

      # Find the most similar existing point using cosine similarity
      existing_embeddings = Enum.take(embeddings, length(embeddings) - 1)

      if length(existing_embeddings) == 0 do
        # First point after empty - return origin
        [{0.0, 0.0, 0.0}]
      else
        # Compute similarity to find nearest neighbor
        {nearest_idx, _} = find_nearest_neighbor(new_flat, existing_embeddings)
        {nx, ny, nz} = Enum.at(prev_coords, nearest_idx)

        # Place new point near its nearest neighbor with small offset
        # Use centroid of nearest neighbors for more stable placement
        offset_scale = 0.1
        key = Nx.Random.key(:erlang.phash2(new_flat))
        {offsets, _} = Nx.Random.normal(key, shape: {3}, type: :f32)
        [ox, oy, oz] = Nx.to_flat_list(offsets)

        new_coord = {
          nx + ox * offset_scale,
          ny + oy * offset_scale,
          nz + oz * offset_scale
        }

        prev_coords ++ [new_coord]
      end
    rescue
      e ->
        Logger.warning("Incremental update failed: #{Exception.message(e)}, falling back to full")
        compute_reduction(embeddings)
    end
  end

  defp find_nearest_neighbor(new_embedding, existing_embeddings) do
    new_norm = Nx.sqrt(Nx.sum(Nx.pow(new_embedding, 2)))

    existing_embeddings
    |> Enum.with_index()
    |> Enum.map(fn {emb, idx} ->
      flat = Nx.flatten(emb)
      # Ensure same dimensions
      dim = min(Nx.size(new_embedding), Nx.size(flat))
      new_slice = Nx.slice(new_embedding, [0], [dim])
      flat_slice = Nx.slice(flat, [0], [dim])

      flat_norm = Nx.sqrt(Nx.sum(Nx.pow(flat_slice, 2)))
      dot = Nx.sum(Nx.multiply(new_slice, flat_slice))
      similarity = Nx.divide(dot, Nx.multiply(new_norm, flat_norm)) |> Nx.to_number()
      {idx, similarity}
    end)
    |> Enum.max_by(fn {_idx, sim} -> sim end)
  end

  @doc """
  Invalidates the cache for a specific blackboard.

  Call this when new trajectory points are added.
  """
  @spec invalidate_cache(integer()) :: :ok
  def invalidate_cache(blackboard_id) do
    ensure_cache_table()

    # Delete all cache entries for this blackboard
    :ets.select_delete(@ets_table, [
      {{{blackboard_id, :_}, :_}, [], [true]}
    ])

    :ok
  end

  # Private functions

  defp compute_reduction(embeddings) do
    n_samples = length(embeddings)

    try do
      # Convert to matrix and normalize dimensions
      matrix = embeddings_to_matrix(embeddings)
      dim = Nx.axis_size(matrix, 1)

      # Apply PCA to reduce to intermediate dimension
      pca_result =
        if dim > @pca_intermediate_dim do
          apply_pca(matrix, @pca_intermediate_dim)
        else
          matrix
        end

      # For small datasets, use PCA directly to 3D (much faster than t-SNE)
      # t-SNE is only beneficial with more points for meaningful neighbor relationships
      if n_samples < @tsne_min_points do
        # Use PCA to 3D directly - fast and stable for small datasets
        apply_pca_to_3d(pca_result)
      else
        # Apply t-SNE to get final 3D coordinates
        tsne_result = apply_tsne(pca_result, @tsne_output_dim)

        # Convert to list of tuples
        tsne_result
        |> Nx.to_list()
        |> Enum.map(fn [x, y, z] -> {x, y, z} end)
      end
    rescue
      e ->
        Logger.warning("Trajectory reduction failed: #{Exception.message(e)}, using fallback")
        simple_projection(embeddings)
    end
  end

  # Fast PCA to 3D for small datasets
  defp apply_pca_to_3d(matrix) do
    dim = Nx.axis_size(matrix, 1)

    if dim <= 3 do
      # Already low-dimensional, pad with zeros if needed
      matrix
      |> Nx.to_list()
      |> Enum.map(fn row ->
        case row do
          [x, y, z | _] -> {x, y, z}
          [x, y] -> {x, y, 0.0}
          [x] -> {x, 0.0, 0.0}
          _ -> {0.0, 0.0, 0.0}
        end
      end)
    else
      # Apply PCA to reduce to exactly 3D
      pca_3d = apply_pca(matrix, 3)

      pca_3d
      |> Nx.to_list()
      |> Enum.map(fn [x, y, z] -> {x, y, z} end)
    end
  end

  defp embeddings_to_matrix(embeddings) do
    # Flatten each embedding and stack into matrix
    flattened = Enum.map(embeddings, &Nx.flatten/1)

    # Get target dimension (use first embedding's dimension)
    target_dim = Nx.size(hd(flattened))

    # Normalize all embeddings to same dimension
    normalized =
      Enum.map(flattened, fn emb ->
        emb_dim = Nx.size(emb)

        cond do
          emb_dim == target_dim ->
            emb

          emb_dim > target_dim ->
            # Truncate larger embeddings
            Nx.slice(emb, [0], [target_dim])

          true ->
            # Pad smaller embeddings with zeros
            pad_size = target_dim - emb_dim
            Nx.concatenate([emb, Nx.broadcast(0.0, {pad_size})])
        end
      end)

    # Stack into matrix
    normalized
    |> Enum.map(&Nx.to_flat_list/1)
    |> Nx.tensor(type: :f32)
  end

  defp apply_pca(matrix, n_components) do
    # Center the data
    mean = Nx.mean(matrix, axes: [0])
    centered = Nx.subtract(matrix, mean)

    # Compute covariance matrix
    n = Nx.axis_size(centered, 0)
    cov = Nx.dot(Nx.transpose(centered), centered) |> Nx.divide(n - 1)

    # Eigendecomposition
    {eigenvalues, eigenvectors} = Nx.LinAlg.eigh(cov)

    # Sort by eigenvalue magnitude (descending)
    # eigh returns eigenvalues in ascending order, so we reverse
    top_indices = get_top_k_indices(eigenvalues, n_components)

    # Select top eigenvectors
    projection_matrix = gather_columns(eigenvectors, top_indices)

    # Project data
    Nx.dot(centered, projection_matrix)
  end

  defp get_top_k_indices(eigenvalues, k) do
    # Get indices of top k eigenvalues (largest magnitude)
    eigenvalues
    |> Nx.to_flat_list()
    |> Enum.with_index()
    |> Enum.sort_by(fn {val, _idx} -> -abs(val) end)
    |> Enum.take(k)
    |> Enum.map(fn {_val, idx} -> idx end)
  end

  defp gather_columns(matrix, indices) do
    # Gather specific columns from matrix
    columns =
      Enum.map(indices, fn idx ->
        Nx.slice(matrix, [0, idx], [Nx.axis_size(matrix, 0), 1])
      end)

    Nx.concatenate(columns, axis: 1)
  end

  defp apply_tsne(matrix, n_components) do
    n_samples = Nx.axis_size(matrix, 0)

    # Adjust perplexity for small datasets
    perplexity = min(@tsne_perplexity, (n_samples - 1) / 3)
    perplexity = max(perplexity, 1.0)

    # Use Scholar's t-SNE implementation
    Scholar.Manifold.TSNE.fit(matrix,
      num_components: n_components,
      perplexity: perplexity,
      learning_rate: @tsne_learning_rate,
      num_iters: @tsne_iterations,
      key: Nx.Random.key(42)
    )
  end

  defp simple_projection(embeddings) do
    # Fallback: project onto first 3 dimensions
    Enum.map(embeddings, fn emb ->
      flat = Nx.flatten(emb)
      dim = Nx.size(flat)

      if dim >= 3 do
        [x, y, z | _] = Nx.to_flat_list(flat) |> Enum.take(3)
        {x, y, z}
      else
        {0.0, 0.0, 0.0}
      end
    end)
  end
end
