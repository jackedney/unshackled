defmodule Unshackled.Visualization.SupportTest do
  use ExUnit.Case, async: true

  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Visualization.Support

  describe "plot_timeline/1" do
    test "returns empty plot for empty list" do
      result = Support.plot_timeline([])
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

      result = Support.plot_timeline([point])
      assert {:ok, spec} = result
      assert spec["mark"] == "text"
    end

    test "creates timeline plot with valid trajectory points" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "First claim",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Second claim",
          support_strength: 0.6
        },
        %TrajectoryPoint{
          cycle_number: 3,
          embedding_vector: create_embedding([3.0, 4.0, 5.0]),
          claim_text: "Third claim",
          support_strength: 0.7
        }
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result
      assert spec["$schema"] == "https://vega.github.io/schema/vega-lite/v5.json"
      assert spec["width"] == 800
      assert spec["height"] == 600
      assert is_list(spec["layer"])
      assert length(spec["layer"]) == 5
    end

    test "includes death threshold line at 0.2" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.3
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.4
        }
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      death_layer =
        Enum.find(layers, fn layer ->
          Map.get(layer, "mark", %{})["type"] == "rule" and
            Map.get(layer, "mark", %{})["stroke"] == "#ff0000"
        end)

      assert death_layer != nil
      assert death_layer["mark"]["strokeDash"] == [5, 5]
      assert hd(death_layer["data"]["values"])["y"] == 0.2
    end

    test "includes graduation threshold line at 0.85" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.8
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.9
        }
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      grad_layer =
        Enum.find(layers, fn layer ->
          Map.get(layer, "mark", %{})["type"] == "rule" and
            Map.get(layer, "mark", %{})["stroke"] == "#00ff00"
        end)

      assert grad_layer != nil
      assert grad_layer["mark"]["strokeDash"] == [5, 5]
      assert hd(grad_layer["data"]["values"])["y"] == 0.85
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

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      line_layer =
        Enum.find(layers, fn layer -> Map.get(layer, "mark", %{})["type"] == "line" end)

      assert line_layer != nil
      assert line_layer["mark"]["opacity"] == 0.7
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

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      point_layer =
        Enum.find(layers, fn layer -> Map.get(layer, "mark", %{})["type"] == "circle" end)

      assert point_layer != nil
      assert point_layer["encoding"]["color"]["scale"]["domain"] == [0.2, 0.85]
      assert point_layer["encoding"]["color"]["scale"]["range"] == ["#ff0000", "#00ff00"]
    end

    test "X-axis shows cycle number" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 10,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.6
        }
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      point_layer =
        Enum.find(layers, fn layer -> Map.get(layer, "mark", %{})["type"] == "circle" end)

      assert point_layer != nil
      assert point_layer["encoding"]["x"]["field"] == "cycle"
      assert point_layer["encoding"]["x"]["type"] == "quantitative"
    end

    test "Y-axis shows support strength" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.6
        }
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      point_layer =
        Enum.find(layers, fn layer -> Map.get(layer, "mark", %{})["type"] == "circle" end)

      assert point_layer != nil
      assert point_layer["encoding"]["y"]["field"] == "support"
      assert point_layer["encoding"]["y"]["type"] == "quantitative"
    end

    test "handles 45-cycle trajectory with graduation at cycle 45" do
      points =
        Enum.map(1..45, fn i ->
          support = 0.5 + i * 0.008

          %TrajectoryPoint{
            cycle_number: i,
            embedding_vector: create_embedding([i * 0.1, i * 0.2, i * 0.3]),
            claim_text: "Claim #{i}",
            support_strength: support
          }
        end)

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result
      assert spec["$schema"] == "https://vega.github.io/schema/vega-lite/v5.json"
      assert is_list(spec["layer"])
    end

    test "annotates critic objections when agent contributions provided" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.4
        },
        %TrajectoryPoint{
          cycle_number: 3,
          embedding_vector: create_embedding([3.0, 4.0, 5.0]),
          claim_text: "Claim 3",
          support_strength: 0.3
        }
      ]

      contributions = [
        %AgentContribution{
          cycle_number: 2,
          agent_role: "critic",
          accepted: true
        }
      ]

      result = Support.plot_timeline(points, agent_contributions: contributions)
      assert {:ok, spec} = result

      layers = spec["layer"]

      annotation_layer =
        Enum.find(layers, fn layer ->
          mark = Map.get(layer, "mark", %{})

          mark["type"] == "text" and
            Map.get(mark, "opacity", 1) != 0 and
            length(Map.get(layer, "data", %{"values" => []})["values"]) > 0
        end)

      assert annotation_layer != nil
      assert length(annotation_layer["data"]["values"]) > 0

      annotation_values = annotation_layer["data"]["values"]
      assert Enum.any?(annotation_values, fn val -> is_binary(val[:text]) and val[:x] == 2 end)
    end

    test "annotates perturber pivots when agent contributions provided" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 3,
          embedding_vector: create_embedding([3.0, 4.0, 5.0]),
          claim_text: "Claim 3",
          support_strength: 0.6
        }
      ]

      contributions = [
        %AgentContribution{
          cycle_number: 2,
          agent_role: "perturber",
          accepted: true
        }
      ]

      result = Support.plot_timeline(points, agent_contributions: contributions)
      assert {:ok, spec} = result

      layers = spec["layer"]

      annotation_layer =
        Enum.find(layers, fn layer ->
          mark = Map.get(layer, "mark", %{})

          mark["type"] == "text" and
            Map.get(mark, "opacity", 1) != 0 and
            length(Map.get(layer, "data", %{"values" => []})["values"]) > 0
        end)

      assert annotation_layer != nil
      assert length(annotation_layer["data"]["values"]) > 0

      annotation_values = annotation_layer["data"]["values"]
      assert Enum.any?(annotation_values, fn val -> is_binary(val[:text]) and val[:x] == 2 end)
    end

    test "filters out non-accepted contributions from annotations" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Claim 1",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Claim 2",
          support_strength: 0.4
        }
      ]

      contributions = [
        %AgentContribution{
          cycle_number: 1,
          agent_role: "critic",
          accepted: false
        },
        %AgentContribution{
          cycle_number: 2,
          agent_role: "critic",
          accepted: true
        }
      ]

      result = Support.plot_timeline(points, agent_contributions: contributions)
      assert {:ok, spec} = result

      layers = spec["layer"]

      annotation_layer =
        Enum.find(layers, fn layer -> Map.get(layer, "mark", %{})["type"] == "text" end)

      assert annotation_layer != nil
      assert length(annotation_layer["data"]["values"]) == 1
    end

    test "handles timeline point maps" do
      points = [
        %{cycle: 1, support: 0.5, claim: "Claim 1"},
        %{cycle: 2, support: 0.6, claim: "Claim 2"}
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result
      assert spec["$schema"] == "https://vega.github.io/schema/vega-lite/v5.json"
    end

    test "handles error for invalid input" do
      result = Support.plot_timeline("not a list")
      assert {:error, _reason} = result
    end

    test "includes tooltips with cycle, support, and claim" do
      points = [
        %TrajectoryPoint{
          cycle_number: 1,
          embedding_vector: create_embedding([1.0, 2.0, 3.0]),
          claim_text: "Test claim",
          support_strength: 0.5
        },
        %TrajectoryPoint{
          cycle_number: 2,
          embedding_vector: create_embedding([2.0, 3.0, 4.0]),
          claim_text: "Another claim",
          support_strength: 0.6
        }
      ]

      result = Support.plot_timeline(points)
      assert {:ok, spec} = result

      layers = spec["layer"]

      point_layer =
        Enum.find(layers, fn layer -> Map.get(layer, "mark", %{})["type"] == "circle" end)

      assert point_layer != nil
      tooltip = point_layer["encoding"]["tooltip"]
      assert length(tooltip) == 3
      assert Enum.any?(tooltip, fn t -> t["title"] == "Cycle" end)
      assert Enum.any?(tooltip, fn t -> t["title"] == "Support" end)
      assert Enum.any?(tooltip, fn t -> t["title"] == "Claim" end)
    end
  end

  defp create_embedding(values) do
    tensor = Nx.tensor(values, type: :f32)
    :erlang.term_to_binary(tensor)
  end
end
