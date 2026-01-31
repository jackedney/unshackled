defmodule Unshackled.Embedding.SimilarityTest do
  use ExUnit.Case, async: true
  alias Unshackled.Embedding.Similarity
  alias Unshackled.Embedding.TrajectoryPoint

  describe "cosine_similarity/2" do
    test "identical vectors return 1.0" do
      vec1 = Nx.tensor([1.0, 2.0, 3.0])
      vec2 = Nx.tensor([1.0, 2.0, 3.0])

      assert {:ok, similarity} = Similarity.cosine_similarity(vec1, vec2)
      assert_in_delta similarity, 1.0, 0.000001
    end

    test "orthogonal vectors return 0.0" do
      vec1 = Nx.tensor([1.0, 0.0])
      vec2 = Nx.tensor([0.0, 1.0])

      assert {:ok, similarity} = Similarity.cosine_similarity(vec1, vec2)
      assert_in_delta similarity, 0.0, 0.000001
    end

    test "vectors with positive angle return similarity between 0 and 1" do
      vec1 = Nx.tensor([1.0, 1.0])
      vec2 = Nx.tensor([1.0, 2.0])

      assert {:ok, similarity} = Similarity.cosine_similarity(vec1, vec2)
      assert similarity > 0.0
      assert similarity < 1.0
    end

    test "opposite vectors return -1.0" do
      vec1 = Nx.tensor([1.0, 2.0, 3.0])
      vec2 = Nx.tensor([-1.0, -2.0, -3.0])

      assert {:ok, similarity} = Similarity.cosine_similarity(vec1, vec2)
      assert_in_delta similarity, -1.0, 0.000001
    end

    test "vectors with different dimensions return error" do
      vec1 = Nx.tensor([1.0, 2.0])
      vec2 = Nx.tensor([1.0, 2.0, 3.0])

      assert {:error, reason} = Similarity.cosine_similarity(vec1, vec2)
      assert reason =~ "same dimensions"
    end

    test "non-tensor inputs return error" do
      assert {:error, _} = Similarity.cosine_similarity([1, 2, 3], [1, 2, 3])
      assert {:error, _} = Similarity.cosine_similarity(Nx.tensor([1, 2]), [1, 2])
    end

    test "zero vectors produce undefined result (division by zero)" do
      vec1 = Nx.tensor([0.0, 0.0, 0.0])
      vec2 = Nx.tensor([1.0, 2.0, 3.0])

      assert {:ok, similarity} = Similarity.cosine_similarity(vec1, vec2)
      assert similarity != similarity or similarity == :nan
    end
  end

  describe "euclidean_distance/2" do
    test "calculates correct distance between 3D vectors" do
      vec1 = Nx.tensor([1.0, 2.0, 3.0])
      vec2 = Nx.tensor([4.0, 5.0, 6.0])

      assert {:ok, distance} = Similarity.euclidean_distance(vec1, vec2)
      assert_in_delta distance, :math.sqrt(27), 0.000001
    end

    test "calculates correct distance between 2D vectors" do
      vec1 = Nx.tensor([0.0, 0.0])
      vec2 = Nx.tensor([3.0, 4.0])

      assert {:ok, distance} = Similarity.euclidean_distance(vec1, vec2)
      assert_in_delta distance, 5.0, 0.000001
    end

    test "identical vectors have distance 0.0" do
      vec1 = Nx.tensor([1.0, 2.0, 3.0])
      vec2 = Nx.tensor([1.0, 2.0, 3.0])

      assert {:ok, distance} = Similarity.euclidean_distance(vec1, vec2)
      assert_in_delta distance, 0.0, 0.000001
    end

    test "vectors with different dimensions return error" do
      vec1 = Nx.tensor([1.0, 2.0])
      vec2 = Nx.tensor([1.0, 2.0, 3.0])

      assert {:error, reason} = Similarity.euclidean_distance(vec1, vec2)
      assert reason =~ "same dimensions"
    end

    test "non-tensor inputs return error" do
      assert {:error, _} = Similarity.euclidean_distance([1, 2], [3, 4])
      assert {:error, _} = Similarity.euclidean_distance(Nx.tensor([1, 2]), [3, 4])
    end
  end

  describe "nearest_neighbors/3" do
    test "finds k nearest neighbors sorted by distance" do
      query = Nx.tensor([0.5, 0.5])

      points = [
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([0.1, 0.1]),
          claim_text: "far"
        },
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([0.6, 0.6]),
          claim_text: "close"
        },
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([0.55, 0.55]),
          claim_text: "closer"
        },
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([0.9, 0.9]),
          claim_text: "farther"
        }
      ]

      assert {:ok, neighbors} = Similarity.nearest_neighbors(query, points, 2)
      assert length(neighbors) == 2

      [{dist1, pt1}, {dist2, _pt2}] = neighbors
      assert dist1 <= dist2
      assert pt1.claim_text == "close" or pt1.claim_text == "closer"
    end

    test "finds all neighbors when k exceeds number of points" do
      query = Nx.tensor([0.5, 0.5])

      points = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.1, 0.1])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.9, 0.9])}
      ]

      assert {:ok, neighbors} = Similarity.nearest_neighbors(query, points, 5)
      assert length(neighbors) == 2
    end

    test "returns empty list for empty points" do
      query = Nx.tensor([0.5, 0.5])
      points = []

      assert {:ok, neighbors} = Similarity.nearest_neighbors(query, points, 5)
      assert neighbors == []
    end

    test "handles points with binary-encoded embeddings" do
      query = Nx.tensor([0.5, 0.5])

      points = [
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([0.6, 0.6]) |> :erlang.term_to_binary(),
          claim_text: "encoded"
        }
      ]

      assert {:ok, neighbors} = Similarity.nearest_neighbors(query, points, 1)
      assert length(neighbors) == 1
      assert hd(neighbors) |> elem(1) |> Map.get(:claim_text) == "encoded"
    end

    test "returns error for k <= 0" do
      query = Nx.tensor([0.5, 0.5])
      points = [%TrajectoryPoint{embedding_vector: Nx.tensor([0.1, 0.1])}]

      assert {:error, reason} = Similarity.nearest_neighbors(query, points, 0)
      assert reason =~ "positive integer"

      assert {:error, reason} = Similarity.nearest_neighbors(query, points, -1)
      assert reason =~ "positive integer"
    end

    test "returns error when points is not a list" do
      query = Nx.tensor([0.5, 0.5])

      assert {:error, reason} = Similarity.nearest_neighbors(query, "not a list", 2)
      assert reason =~ "list"
    end

    test "returns error when query is not Nx.Tensor" do
      assert {:error, reason} = Similarity.nearest_neighbors([0.5, 0.5], [], 2)
      assert reason =~ "Nx.Tensor"
    end

    test "filters out points with invalid embeddings" do
      query = Nx.tensor([0.5, 0.5])

      points = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.6, 0.6])},
        %TrajectoryPoint{embedding_vector: "invalid encoding"}
      ]

      assert {:ok, neighbors} = Similarity.nearest_neighbors(query, points, 5)
      assert length(neighbors) == 1
    end
  end

  describe "trajectory_distance/2" do
    test "computes DTW distance between trajectories" do
      traj1 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 2.0])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([2.0, 3.0])}
      ]

      traj2 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.5, 2.5])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([2.5, 3.5])}
      ]

      assert {:ok, distance} = Similarity.trajectory_distance(traj1, traj2)
      assert is_float(distance)
      assert distance > 0.0
    end

    test "returns 0.0 for identical trajectories" do
      traj = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 2.0])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([2.0, 3.0])}
      ]

      assert {:ok, distance} = Similarity.trajectory_distance(traj, traj)
      assert_in_delta distance, 0.0, 0.000001
    end

    test "returns 0.0 for empty trajectories" do
      assert {:ok, distance} = Similarity.trajectory_distance([], [])
      assert_in_delta distance, 0.0, 0.000001
    end

    test "returns 0.0 for single empty trajectory" do
      traj = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 2.0])}
      ]

      assert {:ok, distance} = Similarity.trajectory_distance(traj, [])
      assert_in_delta distance, 0.0, 0.000001
    end

    test "handles trajectories of different lengths" do
      traj1 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 2.0])}
      ]

      traj2 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([2.0, 3.0])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([3.0, 4.0])}
      ]

      assert {:ok, distance} = Similarity.trajectory_distance(traj1, traj2)
      assert is_float(distance)
      assert distance > 0.0
    end

    test "handles binary-encoded embeddings in trajectories" do
      traj1 = [
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([1.0, 2.0]) |> :erlang.term_to_binary()
        }
      ]

      traj2 = [
        %TrajectoryPoint{
          embedding_vector: Nx.tensor([2.0, 3.0]) |> :erlang.term_to_binary()
        }
      ]

      assert {:ok, distance} = Similarity.trajectory_distance(traj1, traj2)
      assert is_float(distance)
    end

    test "returns error for non-list inputs" do
      assert {:error, reason} = Similarity.trajectory_distance("not a list", [])
      assert reason =~ "list"
    end

    test "returns error when trajectory has invalid embedding" do
      traj1 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 2.0])}
      ]

      traj2 = [
        %TrajectoryPoint{embedding_vector: "invalid"}
      ]

      assert {:error, reason} = Similarity.trajectory_distance(traj1, traj2)
      assert reason =~ "Failed to decode"
    end

    test "DTW allows non-linear alignment" do
      traj1 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.0, 1.0])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([2.0, 2.0])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([3.0, 3.0])}
      ]

      traj2 = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([1.5, 1.5])},
        %TrajectoryPoint{embedding_vector: Nx.tensor([2.5, 2.5])}
      ]

      assert {:ok, distance} = Similarity.trajectory_distance(traj1, traj2)
      assert is_float(distance)
      assert distance > 0.0
    end

    test "find 5 nearest neighbors to current claim in trajectory history" do
      query = Nx.tensor([0.5, 0.5])

      trajectory = [
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.1, 0.1]), claim_text: "very far"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.4, 0.4]), claim_text: "far"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.45, 0.45]), claim_text: "closer"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.55, 0.55]), claim_text: "close1"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.6, 0.6]), claim_text: "close2"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.7, 0.7]), claim_text: "close3"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.8, 0.8]), claim_text: "close4"},
        %TrajectoryPoint{embedding_vector: Nx.tensor([0.9, 0.9]), claim_text: "close5"}
      ]

      assert {:ok, neighbors} = Similarity.nearest_neighbors(query, trajectory, 5)
      assert length(neighbors) == 5

      distances = Enum.map(neighbors, fn {dist, _pt} -> dist end)
      assert Enum.all?(Enum.zip(distances, tl(distances)), fn {d1, d2} -> d1 <= d2 end)
    end
  end
end
