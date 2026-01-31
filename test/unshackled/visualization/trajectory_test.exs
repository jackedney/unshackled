defmodule Unshackled.Visualization.TrajectoryTest do
  use ExUnit.Case, async: true

  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Visualization.Trajectory

  describe "plot_2d/1" do
    test "returns empty plot for empty list" do
      result = Trajectory.plot_2d([])
      assert {:ok, spec} = result
      assert spec["mark"] == "text"
      assert length(spec["data"]["values"]) == 1
      assert hd(spec["data"]["values"])["text"] == "No trajectory data"
    end

    test "returns empty plot for single point" do
      point = %TrajectoryPoint{
        cycle_number: 1,
        embedding_vector: create_embedding([1.0, 2.0, 3.0]),
        claim_text: "Test claim",
        support_strength: 0.5
      }

      result = Trajectory.plot_2d([point])
      assert {:ok, spec} = result
      assert spec["mark"] == "text"
    end

    test "creates 2D plot with valid trajectory points" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0, 4.0, 5.0]),
          claim_text: "First claim",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0, 5.0, 6.0]),
          claim_text: "Second claim",
          support_strength: 0.6
        },
        %TrajectoryPoint{
          cycle_number: 3,
          embedding_vector: create_embedding([3.0, 4.0, 5.0, 6.0, 7.0]),
          claim_text: "Third claim",
          support_strength: 0.7
        }
      ]

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result
      assert spec["$schema"] == "https://vega.github.io/schema/vega-lite/v5.json"
      assert spec["width"] == 800
      assert spec["height"] == 600
      assert is_list(spec["layer"])
      assert length(spec["layer"]) == 4
    end

    test "correctly identifies cemetery points (support <= 0.2)" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Active claim",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Dead claim",
          support_strength: 0.2
        }
      ]

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result

      layers = spec["layer"]
      cemetery_layer = Enum.find(layers, fn layer -> layer["mark"]["type"] == "text" end)

      assert cemetery_layer != nil
      assert cemetery_layer["mark"]["color"] == "#ff0000"
      assert cemetery_layer["encoding"]["text"]["value"] == "✕"
    end

    test "correctly identifies graduated points (support >= 0.85)" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Active claim",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Graduated claim",
          support_strength: 0.85
        }
      ]

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      graduated_layer =
        Enum.find(layers, fn layer ->
          Map.get(layer, "mark", %{})["type"] == "text" and
            Map.get(layer, "mark", %{})["color"] == "#00ff00"
        end)

      assert graduated_layer != nil
      assert graduated_layer["encoding"]["text"]["value"] == "★"
    end

    test "includes line connecting trajectory points" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "First",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Second",
          support_strength: 0.6
        }
      ]

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result

      layers = spec["layer"]
      line_layer = Enum.find(layers, fn layer -> layer["mark"]["type"] == "line" end)

      assert line_layer != nil
      assert line_layer["mark"]["opacity"] == 0.5
    end

    test "includes colored points based on support strength" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Low support",
          support_strength: 0.3
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "High support",
          support_strength: 0.8
        }
      ]

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result

      layers = spec["layer"]
      point_layer = Enum.find(layers, fn layer -> layer["mark"]["type"] == "circle" end)

      assert point_layer != nil
      assert point_layer["encoding"]["color"]["scale"]["domain"] == [0.2, 0.9]
      assert point_layer["encoding"]["color"]["scale"]["range"] == ["#ff0000", "#00ff00"]
    end

    test "includes sized points based on cycle number" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Early point",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 50,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Late point",
          support_strength: 0.6
        }
      ]

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result

      layers = spec["layer"]
      point_layer = Enum.find(layers, fn layer -> layer["mark"]["type"] == "circle" end)

      assert point_layer != nil
      assert point_layer["encoding"]["size"]["scale"]["domain"] == [0, 50]
      assert point_layer["encoding"]["size"]["scale"]["range"] == [50, 300]
    end

    test "handles error for invalid input" do
      result = Trajectory.plot_2d("not a list")
      assert {:error, _reason} = result
    end

    test "handles 50-cycle trajectory" do
      points =
        Enum.map(1..50, fn i ->
          %TrajectoryPoint{
            cycle_number: i,
            embedding_vector: create_embedding([i * 0.1, i * 0.2, i * 0.3]),
            claim_text: "Claim #{i}",
            support_strength: 0.5 + i * 0.008
          }
        end)

      result = Trajectory.plot_2d(points)
      assert {:ok, spec} = result
      assert spec["$schema"] == "https://vega.github.io/schema/vega-lite/v5.json"
      assert is_list(spec["layer"])
    end
  end

  defp create_embedding(values) do
    tensor = Nx.tensor(values, type: :f32)
    :erlang.term_to_binary(tensor)
  end
end
