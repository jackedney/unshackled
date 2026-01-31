defmodule Unshackled.Embedding.NoveltyTest do
  use ExUnit.Case, async: true
  alias Unshackled.Embedding.Novelty

  describe "calculate_novelty/2" do
    test "returns 1.0 for empty trajectory history" do
      claim_embedding = Nx.tensor([1.0, 2.0])
      trajectory = []

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert_in_delta novelty, 1.0, 0.000001
    end

    test "calculates higher novelty for far claim" do
      trajectory = [
        %{embedding_vector: Nx.tensor([0.0, 0.0])},
        %{embedding_vector: Nx.tensor([1.0, 1.0])}
      ]

      claim_embedding = Nx.tensor([10.0, 10.0])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert novelty > 0.5
    end

    test "calculates lower novelty for near claim" do
      trajectory = [
        %{embedding_vector: Nx.tensor([1.0, 2.0])},
        %{embedding_vector: Nx.tensor([2.0, 3.0])}
      ]

      claim_embedding = Nx.tensor([1.1, 2.1])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert novelty < 0.5
    end

    test "calculates very low novelty for nearly identical claim" do
      trajectory = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])}
      ]

      claim_embedding = Nx.tensor([1.001, 2.001, 3.001])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert novelty < 0.1
    end

    test "normalizes novelty to 0.0-1.0 range" do
      trajectory = [
        %{embedding_vector: Nx.tensor([0.0, 0.0])}
      ]

      claim_embeddings = [
        Nx.tensor([0.0, 0.0]),
        Nx.tensor([1.0, 1.0]),
        Nx.tensor([10.0, 10.0])
      ]

      Enum.each(claim_embeddings, fn embedding ->
        assert {:ok, novelty} = Novelty.calculate_novelty(embedding, trajectory)
        assert novelty >= 0.0
        assert novelty <= 1.0
      end)
    end

    test "handles binary-encoded embeddings" do
      trajectory = [
        %{embedding_vector: Nx.tensor([1.0, 2.0]) |> :erlang.term_to_binary()}
      ]

      claim_embedding = Nx.tensor([5.0, 6.0])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert is_float(novelty)
      assert novelty >= 0.0
      assert novelty <= 1.0
    end

    test "handles mixed embedding formats" do
      trajectory = [
        %{embedding_vector: Nx.tensor([1.0, 2.0])},
        %{embedding_vector: Nx.tensor([2.0, 3.0]) |> :erlang.term_to_binary()}
      ]

      claim_embedding = Nx.tensor([3.0, 4.0])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert is_float(novelty)
    end

    test "returns error for non-tensor claim embedding" do
      trajectory = [%{embedding_vector: Nx.tensor([1.0, 2.0])}]

      assert {:error, reason} = Novelty.calculate_novelty([1, 2], trajectory)
      assert reason =~ "Nx.Tensor"

      assert {:error, reason} = Novelty.calculate_novelty("not a tensor", trajectory)
      assert reason =~ "Nx.Tensor"
    end

    test "returns error for non-list trajectory" do
      claim_embedding = Nx.tensor([1.0, 2.0])

      assert {:error, reason} = Novelty.calculate_novelty(claim_embedding, "not a list")
      assert reason =~ "list"
    end

    test "finds minimum distance across multiple points" do
      trajectory = [
        %{embedding_vector: Nx.tensor([10.0, 10.0])},
        %{embedding_vector: Nx.tensor([5.0, 5.0])},
        %{embedding_vector: Nx.tensor([1.0, 1.0])}
      ]

      claim_embedding = Nx.tensor([1.5, 1.5])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)

      assert {:ok, dist1} =
               Unshackled.Embedding.Similarity.euclidean_distance(
                 claim_embedding,
                 Nx.tensor([1.0, 1.0])
               )

      expected_novelty = min(dist1 / 10.0, 1.0)
      assert_in_delta novelty, expected_novelty, 0.000001
    end
  end

  describe "apply_novelty_bonus/2" do
    test "returns max bonus for novelty score of 1.0" do
      {:ok, boosted} = Novelty.apply_novelty_bonus(1.0, 0.5)
      assert_in_delta boosted, 0.55, 0.000001
    end

    test "returns no bonus for novelty score of 0.0" do
      {:ok, boosted} = Novelty.apply_novelty_bonus(0.0, 0.5)
      assert_in_delta boosted, 0.5, 0.000001
    end

    test "returns proportional bonus for intermediate novelty" do
      {:ok, boosted} = Novelty.apply_novelty_bonus(0.5, 0.5)
      assert_in_delta boosted, 0.525, 0.000001
    end

    test "applies bonus correctly to different base confidences" do
      base_confidences = [0.2, 0.5, 0.8]

      Enum.each(base_confidences, fn base ->
        {:ok, boosted} = Novelty.apply_novelty_bonus(1.0, base)
        assert_in_delta boosted, base + 0.05, 0.000001
      end)
    end

    test "caps novelty bonus at 0.05 for scores above 1.0" do
      {:ok, boosted} = Novelty.apply_novelty_bonus(2.0, 0.5)
      assert_in_delta boosted, 0.55, 0.000001
    end

    test "caps at no bonus for novelty scores below 0.0" do
      {:ok, boosted} = Novelty.apply_novelty_bonus(-0.1, 0.5)
      assert_in_delta boosted, 0.5, 0.000001
    end

    test "clamps novelty score above 1.0" do
      {:ok, boosted} = Novelty.apply_novelty_bonus(1.5, 0.5)
      assert_in_delta boosted, 0.55, 0.000001
    end

    test "returns error for non-number novelty score" do
      assert {:error, reason} = Novelty.apply_novelty_bonus("not a number", 0.5)
      assert reason =~ "number"
    end

    test "returns error for non-number base confidence" do
      assert {:error, reason} = Novelty.apply_novelty_bonus(0.5, "not a number")
      assert reason =~ "number"
    end

    test "returns error for non-number inputs" do
      assert {:error, reason} = Novelty.apply_novelty_bonus("novelty", "confidence")
      assert reason =~ "numbers"
    end

    test "example: Claim in unexplored region gets +0.05 novelty bonus" do
      trajectory = []
      claim_embedding = Nx.tensor([50.0, 50.0])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert_in_delta novelty, 1.0, 0.000001

      assert {:ok, boosted} = Novelty.apply_novelty_bonus(novelty, 0.5)
      assert_in_delta boosted, 0.55, 0.000001
    end

    test "example: Claim near previous position gets +0.00 bonus" do
      trajectory = [
        %{embedding_vector: Nx.tensor([5.0, 5.0])}
      ]

      claim_embedding = Nx.tensor([5.001, 5.001])

      assert {:ok, novelty} = Novelty.calculate_novelty(claim_embedding, trajectory)
      assert novelty < 0.001

      assert {:ok, boosted} = Novelty.apply_novelty_bonus(novelty, 0.5)
      assert_in_delta boosted, 0.5, 0.001
    end
  end
end
