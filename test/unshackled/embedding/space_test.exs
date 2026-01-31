defmodule Unshackled.Embedding.SpaceTest do
  use ExUnit.Case, async: false

  alias Unshackled.Embedding.Space
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Blackboard.Server
  alias Unshackled.Repo
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Space is started by the application supervisor, don't start it again
    :ok
  end

  describe "init/1" do
    test "initializes with ETS table" do
      assert :ets.whereis(:embedding_cache) != :undefined
    end

    test "ETS table has public and read_concurrency options" do
      tid = :ets.whereis(:embedding_cache)

      info = :ets.info(tid)

      assert Keyword.get(info, :protection) == :public
      assert Keyword.get(info, :read_concurrency) == true
    end
  end

  describe "embed_claim/1" do
    # Note: Embedding dimension is 384 (semantic model) or 768 (hash fallback)
    @valid_dims [384, 768]

    test "computes embedding for valid claim text" do
      claim = "The second law of thermodynamics is local rather than universal"

      assert {:ok, embedding} = Space.embed_claim(claim)

      assert %Nx.Tensor{} = embedding
      assert Nx.rank(embedding) == 1
      assert Nx.size(embedding) in @valid_dims
    end

    test "returns same embedding for same claim text (caching)" do
      claim = "Entropy increases locally in closed systems"

      assert {:ok, embedding1} = Space.embed_claim(claim)
      assert {:ok, embedding2} = Space.embed_claim(claim)

      assert embedding1 == embedding2
    end

    test "returns different embeddings for different claims" do
      claim1 = "Thermodynamics is universal"
      claim2 = "Thermodynamics is local"

      assert {:ok, embedding1} = Space.embed_claim(claim1)
      assert {:ok, embedding2} = Space.embed_claim(claim2)

      refute embedding1 == embedding2
    end

    test "embedding vector has correct dimension" do
      claim = "Test claim for dimension check"

      assert {:ok, embedding} = Space.embed_claim(claim)

      # 384 for semantic model, 768 for hash fallback
      assert Nx.size(embedding) in @valid_dims
    end

    test "embedding tensor is f32 type" do
      claim = "Test claim for type check"

      assert {:ok, embedding} = Space.embed_claim(claim)

      assert Nx.type(embedding) == {:f, 32}
    end

    test "returns error for empty string" do
      assert {:error, "Cannot embed empty string"} = Space.embed_claim("")
    end

    test "returns error for whitespace-only string" do
      assert {:error, "Cannot embed empty string"} = Space.embed_claim("   ")
    end

    test "returns error for string with only newlines and tabs" do
      assert {:error, "Cannot embed empty string"} = Space.embed_claim("\n\t\n")
    end

    test "handles special characters in claim text" do
      claim = "Quantum decoherence α → β; ∆S > 0"

      assert {:ok, embedding} = Space.embed_claim(claim)
      assert %Nx.Tensor{} = embedding
      assert Nx.size(embedding) in @valid_dims
    end

    test "handles very long claim text" do
      claim = String.duplicate("This is a test claim. ", 1000)

      assert {:ok, embedding} = Space.embed_claim(claim)
      assert %Nx.Tensor{} = embedding
    end
  end

  describe "embed_state/1" do
    test "computes embedding for blackboard state" do
      state = %Server{
        current_claim: "Local thermodynamics holds",
        support_strength: 0.5,
        cycle_count: 1,
        blackboard_id: 1,
        embedding: nil
      }

      assert {:ok, embedding} = Space.embed_state(state)
      assert %Nx.Tensor{} = embedding
    end

    test "embedding includes claim, support, and cycle information" do
      state1 = %Server{
        current_claim: "Local thermodynamics holds",
        support_strength: 0.5,
        cycle_count: 1,
        blackboard_id: 1
      }

      state2 = %Server{
        current_claim: "Local thermodynamics holds",
        support_strength: 0.7,
        cycle_count: 1,
        blackboard_id: 1
      }

      assert {:ok, embedding1} = Space.embed_state(state1)
      assert {:ok, embedding2} = Space.embed_state(state2)

      refute embedding1 == embedding2
    end

    test "returns same embedding for same state (caching)" do
      state = %Server{
        current_claim: "Thermodynamics is local",
        support_strength: 0.5,
        cycle_count: 10,
        blackboard_id: 1
      }

      assert {:ok, embedding1} = Space.embed_state(state)
      assert {:ok, embedding2} = Space.embed_state(state)

      assert embedding1 == embedding2
    end

    test "embedding vector has extra dimensions for support and cycle" do
      state = %Server{
        current_claim: "Test claim",
        support_strength: 0.5,
        cycle_count: 5,
        blackboard_id: 1
      }

      assert {:ok, embedding} = Space.embed_state(state)

      # Should be claim embedding + 2 (support + normalized cycle)
      # 384 + 2 = 386 (semantic) or 768 + 2 = 770 (hash fallback)
      assert Nx.size(embedding) in [386, 770]
    end
  end

  describe "store_trajectory_point/1" do
    test "stores trajectory point to database" do
      {:ok, embedding} = Space.embed_claim("Test claim")

      point = %{
        blackboard_id: 1,
        cycle_number: 1,
        embedding_vector: embedding,
        claim_text: "Test claim",
        support_strength: 0.5
      }

      assert {:ok, trajectory_point} = Space.store_trajectory_point(point)

      assert trajectory_point.blackboard_id == 1
      assert trajectory_point.cycle_number == 1
      assert trajectory_point.claim_text == "Test claim"
      assert trajectory_point.support_strength == 0.5
      assert is_binary(trajectory_point.embedding_vector)
    end

    test "persisted trajectory point can be retrieved" do
      {:ok, embedding} = Space.embed_claim("Retrievable claim")

      point = %{
        blackboard_id: 2,
        cycle_number: 5,
        embedding_vector: embedding,
        claim_text: "Retrievable claim",
        support_strength: 0.75
      }

      assert {:ok, _} = Space.store_trajectory_point(point)

      retrieved =
        Repo.one(
          from(t in TrajectoryPoint,
            where: t.blackboard_id == 2 and t.cycle_number == 5
          )
        )

      assert retrieved != nil
      assert retrieved.claim_text == "Retrievable claim"
      assert retrieved.support_strength == 0.75
    end

    test "returns error for invalid trajectory point" do
      invalid_point = %{
        blackboard_id: nil,
        cycle_number: 1,
        embedding_vector: Nx.tensor([1.0, 2.0]),
        claim_text: "Invalid",
        support_strength: 0.5
      }

      assert {:error, changeset} = Space.store_trajectory_point(invalid_point)
      assert changeset.valid? == false
    end

    test "converts Nx.Tensor embedding to binary for storage" do
      {:ok, embedding} = Space.embed_claim("Binary storage test")

      point = %{
        blackboard_id: 3,
        cycle_number: 1,
        embedding_vector: embedding,
        claim_text: "Binary storage test",
        support_strength: 0.6
      }

      assert {:ok, trajectory_point} = Space.store_trajectory_point(point)

      assert is_binary(trajectory_point.embedding_vector)
    end
  end

  describe "get_trajectory/1" do
    test "retrieves empty trajectory for non-existent blackboard" do
      assert {:ok, trajectory} = Space.get_trajectory(999_999)
      assert trajectory == []
    end

    test "retrieves trajectory points in order" do
      {:ok, embedding1} = Space.embed_claim("First claim")
      {:ok, embedding2} = Space.embed_claim("Second claim")

      point1 = %{
        blackboard_id: 10,
        cycle_number: 3,
        embedding_vector: embedding1,
        claim_text: "First claim",
        support_strength: 0.5
      }

      point2 = %{
        blackboard_id: 10,
        cycle_number: 5,
        embedding_vector: embedding2,
        claim_text: "Second claim",
        support_strength: 0.7
      }

      assert {:ok, _} = Space.store_trajectory_point(point1)
      assert {:ok, _} = Space.store_trajectory_point(point2)

      assert {:ok, trajectory} = Space.get_trajectory(10)

      assert length(trajectory) == 2
      assert hd(trajectory).cycle_number == 3
      assert List.last(trajectory).cycle_number == 5
    end

    test "retrieves all trajectory points for blackboard" do
      blackboard_id = 20

      for i <- 1..10 do
        {:ok, embedding} = Space.embed_claim("Claim #{i}")

        point = %{
          blackboard_id: blackboard_id,
          cycle_number: i,
          embedding_vector: embedding,
          claim_text: "Claim #{i}",
          support_strength: 0.5
        }

        Space.store_trajectory_point(point)
      end

      assert {:ok, trajectory} = Space.get_trajectory(blackboard_id)
      assert length(trajectory) == 10
    end

    test "stores and retrieves 50 trajectory points" do
      blackboard_id = 50

      for i <- 1..50 do
        {:ok, embedding} = Space.embed_claim("Claim #{i}")

        point = %{
          blackboard_id: blackboard_id,
          cycle_number: i,
          embedding_vector: embedding,
          claim_text: "Claim #{i}",
          support_strength: 0.5 + i / 200.0
        }

        Space.store_trajectory_point(point)
      end

      assert {:ok, trajectory} = Space.get_trajectory(blackboard_id)
      assert length(trajectory) == 50

      Enum.each(trajectory, fn point ->
        assert point.blackboard_id == blackboard_id
        assert is_binary(point.claim_text)
        assert point.support_strength >= 0.5
        assert point.support_strength <= 0.75
      end)
    end
  end

  describe "integration" do
    test "complete workflow: embed claims, store points, retrieve trajectory" do
      blackboard_id = 100

      claims = [
        "Initial claim about local thermodynamics",
        "Revised claim with quantum considerations",
        "Final claim incorporating information theory"
      ]

      points =
        Enum.with_index(claims, 1)
        |> Enum.map(fn {claim, cycle} ->
          {:ok, embedding} = Space.embed_claim(claim)

          point = %{
            blackboard_id: blackboard_id,
            cycle_number: cycle,
            embedding_vector: embedding,
            claim_text: claim,
            support_strength: 0.5 + cycle * 0.1
          }

          assert {:ok, _} = Space.store_trajectory_point(point)

          point
        end)

      assert {:ok, trajectory} = Space.get_trajectory(blackboard_id)

      assert length(trajectory) == 3

      Enum.zip(trajectory, points)
      |> Enum.each(fn {retrieved, original} ->
        assert retrieved.claim_text == original.claim_text
        assert retrieved.cycle_number == original.cycle_number
        assert retrieved.support_strength == original.support_strength
      end)
    end

    test "ETS cache improves performance for repeated embeddings" do
      claim = "Repeated claim for cache test"

      {time1, {:ok, _}} = :timer.tc(fn -> Space.embed_claim(claim) end)
      {time2, {:ok, _}} = :timer.tc(fn -> Space.embed_claim(claim) end)

      assert time2 < time1
    end

    test "multiple concurrent requests for same claim use cache" do
      claim = "Concurrent test claim"

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Space.embed_claim(claim)
          end)
        end

      results = Task.await_many(tasks, 5000)

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end
  end

  describe "negative cases" do
    test "embed_claim with nil returns error" do
      assert {:error, "Cannot embed empty string"} = Space.embed_claim(nil)
    end

    test "embed_state with invalid state type returns error" do
      invalid_state = %{invalid: "state"}

      assert {:error, "Invalid state structure"} = Space.embed_state(invalid_state)
    end

    test "store_trajectory_point without required fields returns error" do
      incomplete_point = %{
        blackboard_id: 1
      }

      assert {:error, changeset} = Space.store_trajectory_point(incomplete_point)
      refute changeset.valid?
    end

    test "get_trajectory with negative blackboard_id returns empty list" do
      assert {:ok, trajectory} = Space.get_trajectory(-1)
      assert trajectory == []
    end

    test "get_trajectory with zero blackboard_id returns empty list" do
      assert {:ok, trajectory} = Space.get_trajectory(0)
      assert trajectory == []
    end
  end
end
