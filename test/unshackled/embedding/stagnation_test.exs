defmodule Unshackled.Embedding.StagnationTest do
  use ExUnit.Case, async: true
  alias Unshackled.Embedding.Stagnation

  describe "detect_stagnation/2" do
    test "detects stagnation with 7 consecutive cycles below threshold" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004])},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004])},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == true
      assert cycles_stagnant == 7
      assert is_number(average_movement)
      assert average_movement > 0.0
      assert average_movement < 0.01
    end

    test "detects stagnation with exactly 5 consecutive cycles below threshold" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004])},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == true
      assert cycles_stagnant == 5
      assert is_number(average_movement)
      assert average_movement > 0.0
    end

    test "does not detect stagnation with 4 consecutive cycles below threshold" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004])},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == false
      assert cycles_stagnant == 4
      assert is_number(average_movement)
    end

    test "resets stagnation counter after large jump in cycle 6" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004])},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([5.0, 6.0, 7.0])},
        %{embedding_vector: Nx.tensor([5.005, 6.005, 7.005])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == false
      assert cycles_stagnant == 1
      assert is_number(average_movement)
    end

    test "returns not stagnant with fewer than 5 trajectory points" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == false
      assert cycles_stagnant == 2
      assert is_number(average_movement)
    end

    test "returns not stagnant with single trajectory point" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == false
      assert cycles_stagnant == 0
      assert average_movement == 0.0
    end

    test "returns not stagnant with empty trajectory points" do
      trajectory_points = []

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == false
      assert cycles_stagnant == 0
      assert average_movement == 0.0
    end

    test "handles binary-encoded embeddings" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0]) |> :erlang.term_to_binary()},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005]) |> :erlang.term_to_binary()},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003]) |> :erlang.term_to_binary()},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004]) |> :erlang.term_to_binary()},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002]) |> :erlang.term_to_binary()},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003]) |> :erlang.term_to_binary()}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == true
      assert cycles_stagnant == 5
      assert is_number(average_movement)
    end

    test "respects different threshold values" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([1.0, 2.0, 3.0])},
        %{embedding_vector: Nx.tensor([1.005, 2.005, 3.005])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])},
        %{embedding_vector: Nx.tensor([1.004, 2.004, 3.004])},
        %{embedding_vector: Nx.tensor([1.002, 2.002, 3.002])},
        %{embedding_vector: Nx.tensor([1.003, 2.003, 3.003])}
      ]

      {is_stagnant_low, _, _} = Stagnation.detect_stagnation(trajectory_points, 0.001)
      {is_stagnant_high, _, _} = Stagnation.detect_stagnation(trajectory_points, 1.0)

      assert is_stagnant_low == false
      assert is_stagnant_high == true
    end

    test "calculates average movement correctly" do
      trajectory_points = [
        %{embedding_vector: Nx.tensor([0.0, 0.0, 0.0])},
        %{embedding_vector: Nx.tensor([0.005, 0.0, 0.0])},
        %{embedding_vector: Nx.tensor([0.005, 0.005, 0.0])},
        %{embedding_vector: Nx.tensor([0.005, 0.005, 0.005])},
        %{embedding_vector: Nx.tensor([0.0, 0.005, 0.005])},
        %{embedding_vector: Nx.tensor([0.0, 0.0, 0.005])}
      ]

      {is_stagnant, _, average_movement} = Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == true

      expected_distance = :math.sqrt(0.005 * 0.005)
      assert_in_delta average_movement, expected_distance, 0.0001
    end

    test "handles invalid embedding data gracefully" do
      trajectory_points = [
        %{embedding_vector: "invalid binary"},
        %{embedding_vector: "another invalid"},
        %{embedding_vector: Nx.tensor([1.0, 2.0])}
      ]

      {is_stagnant, cycles_stagnant, average_movement} =
        Stagnation.detect_stagnation(trajectory_points, 0.01)

      assert is_stagnant == false
      assert cycles_stagnant >= 0
      assert is_number(average_movement)
    end
  end
end
