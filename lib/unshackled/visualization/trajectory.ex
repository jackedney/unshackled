defmodule Unshackled.Visualization.Trajectory do
  @moduledoc """
  Trajectory visualization using VegaLite spec format.

  This module provides 2D visualization data for reasoning trajectories using PCA
  to reduce high-dimensional embeddings to 2D for plotting.

  Visualizations include:
  - 2D scatter plot with PCA-reduced embeddings
  - Points colored by support strength (red to green gradient)
  - Points sized by cycle number (larger = more recent)
  - Connected lines showing trajectory path
  - X symbols for cemetery claims
  - Star symbols for graduated claims
  """

  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Visualization.TrajectoryReducer

  @type trajectory_point_map :: %{
          x: float(),
          y: float(),
          cycle: non_neg_integer(),
          support: float(),
          claim: String.t(),
          status: :active | :cemetery | :graduated
        }

  @type trajectory_3d_point_map :: %{
          x: float(),
          y: float(),
          z: float(),
          cycle: non_neg_integer(),
          support: float(),
          claim: String.t(),
          status: :active | :cemetery | :graduated
        }

  @doc """
  Creates a 2D VegaLite plot of trajectory points using PCA.

  ## Parameters

  - trajectory_points: List of TrajectoryPoint structs or trajectory point maps

  ## Returns

  - VegaLite spec map on success
  - {:error, reason} on failure

  ## Examples

      iex> trajectory_points = [
      ...>   %TrajectoryPoint{cycle_number: 1, embedding_vector: <tensor>, ...},
      ...>   %TrajectoryPoint{cycle_number: 2, embedding_vector: <tensor>, ...}
      ...> ]
      iex> {:ok, spec} = Trajectory.plot_2d(trajectory_points)

      iex> Trajectory.plot_2d([])
      {:ok, %{
        "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
        "mark" => "text",
        "encoding" => %{"text" => %{"field" => "label"}},
        "data" => %{"values" => [%{"label" => "No trajectory data"}]}
      }}

  """
  @spec plot_2d([Unshackled.Embedding.TrajectoryPoint.t()]) :: {:ok, map()} | {:error, String.t()}
  def plot_2d([]) do
    empty_spec()
  end

  def plot_2d([_single_point]) do
    empty_spec()
  end

  def plot_2d(trajectory_points) when is_list(trajectory_points) do
    with {:ok, decoded_points} <- decode_all_embeddings(trajectory_points),
         {:ok, pca_points} <- apply_pca(decoded_points),
         {:ok, all_data} <- prepare_all_visualization_data(pca_points, trajectory_points) do
      spec = build_vegalite_spec(all_data)
      {:ok, spec}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def plot_2d(_) do
    {:error, "Input must be a list of trajectory points"}
  end

  @doc """
  Creates 3D trajectory data for Plotly.js visualization using t-SNE.

  ## Parameters

  - trajectory_points: List of TrajectoryPoint structs
  - blackboard_id: ID for cache lookup

  ## Returns

  - {:ok, %{points: [%{x, y, z, cycle, support, claim, status}]}} on success
  - {:error, reason} on failure
  """
  @spec plot_3d([TrajectoryPoint.t()], integer()) :: {:ok, map()} | {:error, String.t()}
  def plot_3d([], _blackboard_id) do
    {:ok, %{points: []}}
  end

  def plot_3d([single_point], blackboard_id) do
    status = determine_status(single_point)

    point = %{
      x: 0.0,
      y: 0.0,
      z: 0.0,
      cycle: single_point.cycle_number,
      support: single_point.support_strength,
      claim: single_point.claim_text,
      status: status
    }

    {:ok, %{points: [point], blackboard_id: blackboard_id}}
  end

  def plot_3d(trajectory_points, blackboard_id) when is_list(trajectory_points) do
    with {:ok, decoded_embeddings} <- decode_all_embeddings(trajectory_points),
         coords <- TrajectoryReducer.reduce_to_3d(decoded_embeddings, blackboard_id) do
      points =
        trajectory_points
        |> Enum.zip(coords)
        |> Enum.map(fn {point, {x, y, z}} ->
          %{
            x: x,
            y: y,
            z: z,
            cycle: point.cycle_number,
            support: point.support_strength,
            claim: point.claim_text,
            status: determine_status(point)
          }
        end)

      {:ok, %{points: points, blackboard_id: blackboard_id}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def plot_3d(_, _) do
    {:error, "Input must be a list of trajectory points"}
  end

  @spec empty_spec() :: {:ok, map()}
  defp empty_spec do
    spec = %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "width" => 800,
      "height" => 600,
      "mark" => "text",
      "data" => %{
        "values" => [
          %{"text" => "No trajectory data", "x" => 400, "y" => 300, "fontSize" => 20}
        ]
      },
      "encoding" => %{
        "x" => %{"field" => "x", "type" => "quantitative"},
        "y" => %{"field" => "y", "type" => "quantitative"},
        "text" => %{"field" => "text", "type" => "nominal"},
        "fontSize" => %{"field" => "fontSize", "type" => "quantitative"}
      }
    }

    {:ok, spec}
  end

  @spec decode_all_embeddings([TrajectoryPoint.t()]) ::
          {:ok, [Nx.Tensor.t()]} | {:error, String.t()}
  defp decode_all_embeddings(trajectory_points) do
    decoded =
      Enum.map(trajectory_points, fn point ->
        case decode_embedding(point) do
          {:ok, tensor} -> tensor
          _ -> nil
        end
      end)

    if Enum.any?(decoded, &is_nil/1) do
      {:error, "Failed to decode one or more embeddings"}
    else
      {:ok, decoded}
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

  @spec apply_pca([Nx.Tensor.t()]) :: {:ok, [tuple()]} | {:error, String.t()}
  defp apply_pca(embeddings) when length(embeddings) < 2 do
    {:error, "Need at least 2 points for PCA"}
  end

  defp apply_pca(embeddings) do
    # For high-dimensional embeddings, eigendecomposition of the full covariance
    # matrix is too slow. Use a simplified approach that projects onto the first
    # two dimensions after centering, which gives reasonable spread for visualization.
    try do
      matrix = embeddings_to_matrix(embeddings)
      centered = center_data(matrix)

      # Use simple projection onto first two dimensions rather than full PCA
      # This avoids the expensive eigendecomposition of large covariance matrices
      dim = Nx.axis_size(centered, 1)

      if dim > 100 do
        # For high-dimensional data, use random projection (much faster)
        # This preserves distances approximately (Johnson-Lindenstrauss)
        reduced = random_projection_2d(centered)
        points = Nx.to_list(reduced) |> Enum.map(fn [x, y] -> {x, y} end)
        {:ok, points}
      else
        # For low-dimensional data, use full PCA
        covariance = compute_covariance(centered)
        {_eigenvalues, eigenvectors} = eigendecomposition(covariance)

        top_2_eigenvectors =
          eigenvectors
          |> Nx.transpose()
          |> Nx.slice([0, 0], [2, Nx.axis_size(eigenvectors, 0)])

        reduced =
          Nx.dot(centered, Nx.transpose(top_2_eigenvectors))
          |> Nx.to_list()

        points = Enum.map(reduced, fn [x, y] -> {x, y} end)
        {:ok, points}
      end
    rescue
      e -> {:error, "PCA computation failed: #{inspect(e)}"}
    end
  end

  @spec random_projection_2d(Nx.Tensor.t()) :: Nx.Tensor.t()
  defp random_projection_2d(matrix) do
    # Random projection to 2D - fast approximation that preserves distances
    dim = Nx.axis_size(matrix, 1)

    # Use a fixed seed for reproducibility within a session
    key = Nx.Random.key(42)
    {projection_matrix, _} = Nx.Random.normal(key, shape: {dim, 2}, type: :f32)

    # Normalize columns for better scaling
    norms = Nx.sqrt(Nx.sum(Nx.pow(projection_matrix, 2), axes: [0]))
    projection_matrix = Nx.divide(projection_matrix, norms)

    # Project data
    Nx.dot(matrix, projection_matrix)
  end

  @spec embeddings_to_matrix([Nx.Tensor.t()]) :: Nx.Tensor.t()
  defp embeddings_to_matrix(embeddings) do
    flattened = Enum.map(embeddings, &Nx.flatten/1)
    list_of_lists = Enum.map(flattened, &Nx.to_flat_list/1)

    num_points = length(list_of_lists)
    dim = length(hd(list_of_lists))

    Nx.tensor(list_of_lists, type: :f32)
    |> Nx.reshape({num_points, dim})
  end

  @spec center_data(Nx.Tensor.t()) :: Nx.Tensor.t()
  defp center_data(matrix) do
    means = Nx.mean(matrix, axes: [0])
    Nx.subtract(matrix, means)
  end

  @spec compute_covariance(Nx.Tensor.t()) :: Nx.Tensor.t()
  defp compute_covariance(centered_matrix) do
    n = Nx.axis_size(centered_matrix, 0)
    transposed = Nx.transpose(centered_matrix)
    Nx.dot(transposed, centered_matrix) |> Nx.divide(n - 1)
  end

  @spec eigendecomposition(Nx.Tensor.t()) :: {Nx.Tensor.t(), Nx.Tensor.t()}
  defp eigendecomposition(cov_matrix) do
    # Nx.LinAlg.eigh returns {eigenvalues, eigenvectors}
    Nx.LinAlg.eigh(cov_matrix)
  end

  @spec prepare_all_visualization_data([tuple()], [Unshackled.Embedding.TrajectoryPoint.t()]) ::
          {:ok, trajectory_point_map()} | {:error, String.t()}
  defp prepare_all_visualization_data(pca_points, trajectory_points) do
    if length(pca_points) != length(trajectory_points) do
      {:error, "PCA points count doesn't match trajectory points count"}
    else
      data =
        Enum.zip(pca_points, trajectory_points)
        |> Enum.map(fn {pca_point, point} ->
          {x, y} = pca_point
          status = determine_status(point)

          %{
            x: x,
            y: y,
            cycle: point.cycle_number,
            support: point.support_strength,
            claim: point.claim_text,
            status: status
          }
        end)

      {:ok, data}
    end
  end

  @spec determine_status(Unshackled.Embedding.TrajectoryPoint.t()) ::
          :active | :cemetery | :graduated
  defp determine_status(point) do
    cond do
      point.support_strength <= 0.2 -> :cemetery
      point.support_strength >= 0.85 -> :graduated
      true -> :active
    end
  end

  @spec build_vegalite_spec([trajectory_point_map()]) :: map()
  defp build_vegalite_spec(data) do
    base_spec = %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "width" => 800,
      "height" => 600,
      "title" => %{"text" => "Reasoning Trajectory (PCA 2D)", "fontSize" => 16},
      "data" => %{"values" => data},
      "layer" => [
        build_line_layer(data),
        build_point_layer(data),
        build_cemetery_layer(data),
        build_graduated_layer(data)
      ]
    }

    base_spec
  end

  @spec build_line_layer([trajectory_point_map()]) :: map()
  defp build_line_layer(data) when length(data) < 2 do
    %{
      "mark" => %{"type" => "line", "opacity" => 0.5},
      "encoding" => %{},
      "data" => %{"values" => []}
    }
  end

  defp build_line_layer(data) do
    sorted_data = Enum.sort_by(data, & &1.cycle)

    %{
      "mark" => %{"type" => "line", "opacity" => 0.5, "color" => "#666666"},
      "encoding" => %{
        "x" => %{"field" => "x", "type" => "quantitative", "title" => "PC1"},
        "y" => %{"field" => "y", "type" => "quantitative", "title" => "PC2"},
        "order" => %{"field" => "cycle", "type" => "ordinal"}
      },
      "data" => %{"values" => sorted_data}
    }
  end

  @spec build_point_layer([trajectory_point_map()]) :: map()
  defp build_point_layer(data) do
    %{
      "mark" => %{
        "type" => "circle",
        "opacity" => 0.8,
        "tooltip" => true
      },
      "encoding" => %{
        "x" => %{"field" => "x", "type" => "quantitative", "title" => "PC1"},
        "y" => %{"field" => "y", "type" => "quantitative", "title" => "PC2"},
        "size" => %{
          "field" => "cycle",
          "type" => "quantitative",
          "scale" => %{"domain" => [0, 50], "range" => [50, 300]},
          "legend" => %{"title" => "Cycle"}
        },
        "color" => %{
          "field" => "support",
          "type" => "quantitative",
          "scale" => %{
            "domain" => [0.2, 0.9],
            "range" => ["#ff0000", "#00ff00"],
            "type" => "linear"
          },
          "legend" => %{"title" => "Support"}
        },
        "tooltip" => [
          %{"field" => "cycle", "type" => "quantitative", "title" => "Cycle"},
          %{
            "field" => "support",
            "type" => "quantitative",
            "title" => "Support",
            "format" => ".2f"
          },
          %{"field" => "claim", "type" => "nominal", "title" => "Claim"}
        ]
      },
      "data" => %{"values" => data}
    }
  end

  @spec build_cemetery_layer([trajectory_point_map()]) :: map()
  defp build_cemetery_layer(data) do
    cemetery_data = Enum.filter(data, &(&1.status == :cemetery))

    if length(cemetery_data) == 0 do
      %{
        "mark" => %{"type" => "text", "opacity" => 0},
        "encoding" => %{},
        "data" => %{"values" => []}
      }
    else
      %{
        "mark" => %{
          "type" => "text",
          "fontWeight" => "bold",
          "fontSize" => 20,
          "color" => "#ff0000"
        },
        "encoding" => %{
          "x" => %{"field" => "x", "type" => "quantitative"},
          "y" => %{"field" => "y", "type" => "quantitative"},
          "text" => %{"value" => "✕"},
          "tooltip" => [
            %{"field" => "cycle", "type" => "quantitative", "title" => "Cycle (Died)"},
            %{
              "field" => "support",
              "type" => "quantitative",
              "title" => "Final Support",
              "format" => ".2f"
            },
            %{"field" => "claim", "type" => "nominal", "title" => "Claim"}
          ]
        },
        "data" => %{"values" => cemetery_data}
      }
    end
  end

  @spec build_graduated_layer([trajectory_point_map()]) :: map()
  defp build_graduated_layer(data) do
    graduated_data = Enum.filter(data, &(&1.status == :graduated))

    if length(graduated_data) == 0 do
      %{
        "mark" => %{"type" => "text", "opacity" => 0},
        "encoding" => %{},
        "data" => %{"values" => []}
      }
    else
      %{
        "mark" => %{
          "type" => "text",
          "fontWeight" => "bold",
          "fontSize" => 24,
          "color" => "#00ff00"
        },
        "encoding" => %{
          "x" => %{"field" => "x", "type" => "quantitative"},
          "y" => %{"field" => "y", "type" => "quantitative"},
          "text" => %{"value" => "★"},
          "tooltip" => [
            %{"field" => "cycle", "type" => "quantitative", "title" => "Cycle (Graduated)"},
            %{
              "field" => "support",
              "type" => "quantitative",
              "title" => "Final Support",
              "format" => ".2f"
            },
            %{"field" => "claim", "type" => "nominal", "title" => "Claim"}
          ]
        },
        "data" => %{"values" => graduated_data}
      }
    end
  end
end
