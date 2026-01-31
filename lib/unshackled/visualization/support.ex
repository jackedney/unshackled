defmodule Unshackled.Visualization.Support do
  @moduledoc """
  Support strength timeline visualization using VegaLite spec format.

  This module provides timeline visualization data for support_strength over cycles.

  Visualizations include:
  - Line plot showing support_strength over time
  - X-axis: cycle number
  - Y-axis: support_strength (0.0 to 1.0)
  - Horizontal lines at 0.2 (death threshold) and 0.85 (graduation threshold)
  - Color gradient matching support level (red to green)
  - Annotations for major events (Critic objections, Perturber pivots)
  """

  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Agents.AgentContribution

  @type timeline_point :: %{
          cycle: non_neg_integer(),
          support: float(),
          claim: String.t()
        }

  @type event_annotation :: %{
          cycle: non_neg_integer(),
          event_type: :critic_objection | :perturber_pivot,
          label: String.t()
        }

  @death_threshold 0.2
  @graduation_threshold 0.85

  @doc """
  Creates a timeline plot of support strength over cycles.

  ## Parameters

  - trajectory_points: List of TrajectoryPoint structs or timeline point maps
  - options: Keyword list of options
    - agent_contributions: List of AgentContribution structs for event annotations (optional)

  ## Returns

  - VegaLite spec map on success
  - {:error, reason} on failure

  ## Examples

      iex> trajectory_points = [
      ...>   %TrajectoryPoint{cycle_number: 1, support_strength: 0.5, claim_text: "Claim 1"},
      ...>   %TrajectoryPoint{cycle_number: 2, support_strength: 0.6, claim_text: "Claim 2"}
      ...> ]
      iex> {:ok, spec} = Support.plot_timeline(trajectory_points)

      iex> Support.plot_timeline([])
      {:ok, %{
        "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
        "mark" => "text",
        "encoding" => %{"text" => %{"field" => "label"}},
        "data" => %{"values" => [%{"label" => "No trajectory data"}]}
      }}

  """
  @spec plot_timeline([TrajectoryPoint.t() | timeline_point()], keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def plot_timeline([]) do
    empty_spec()
  end

  def plot_timeline(points, opts \\ [])

  def plot_timeline([_single_point], _opts) do
    empty_spec()
  end

  def plot_timeline(trajectory_points, opts) when is_list(trajectory_points) do
    with {:ok, timeline_data} <- prepare_timeline_data(trajectory_points),
         {:ok, annotations} <- prepare_event_annotations(opts[:agent_contributions]) do
      spec = build_vegalite_spec(timeline_data, annotations)
      {:ok, spec}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def plot_timeline(_, _) do
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

  @spec prepare_timeline_data([TrajectoryPoint.t() | timeline_point()]) ::
          {:ok, [timeline_point()]} | {:error, String.t()}
  defp prepare_timeline_data(trajectory_points) do
    data =
      Enum.map(trajectory_points, fn point ->
        case point do
          %TrajectoryPoint{cycle_number: cycle, support_strength: support, claim_text: claim} ->
            %{cycle: cycle, support: support, claim: claim}

          %{cycle: cycle, support: support, claim: claim} ->
            %{cycle: cycle, support: support, claim: claim}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if length(data) < 2 do
      {:error, "Need at least 2 trajectory points for timeline"}
    else
      {:ok, data}
    end
  end

  @spec prepare_event_annotations([AgentContribution.t()] | nil) ::
          {:ok, [event_annotation()]}
  defp prepare_event_annotations(nil), do: {:ok, []}

  defp prepare_event_annotations(agent_contributions) when is_list(agent_contributions) do
    annotations =
      agent_contributions
      |> Enum.filter(fn contribution ->
        contribution.accepted and
          (contribution.agent_role == "critic" or contribution.agent_role == "perturber")
      end)
      |> Enum.map(fn contribution ->
        event_type =
          case contribution.agent_role do
            "critic" -> :critic_objection
            "perturber" -> :perturber_pivot
            _ -> nil
          end

        %{
          cycle: contribution.cycle_number,
          event_type: event_type,
          label:
            case event_type do
              :critic_objection -> "⚠️ Critic"
              :perturber_pivot -> "🔄 Pivot"
              _ -> ""
            end
        }
      end)
      |> Enum.reject(fn %{event_type: type} -> is_nil(type) end)

    {:ok, annotations}
  end

  @spec build_vegalite_spec([timeline_point()], [event_annotation()]) :: map()
  defp build_vegalite_spec(timeline_data, event_annotations) do
    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "width" => 800,
      "height" => 600,
      "title" => %{"text" => "Support Strength Timeline", "fontSize" => 16},
      "data" => %{"values" => timeline_data},
      "layer" => [
        build_death_threshold_layer(),
        build_graduation_threshold_layer(),
        build_line_layer(timeline_data),
        build_point_layer(timeline_data),
        build_event_annotations_layer(event_annotations)
      ]
    }
  end

  @spec build_death_threshold_layer() :: map()
  defp build_death_threshold_layer do
    %{
      "mark" => %{
        "type" => "rule",
        "stroke" => "#ff0000",
        "strokeWidth" => 2,
        "strokeDash" => [5, 5]
      },
      "data" => %{"values" => [%{"y" => @death_threshold}]},
      "encoding" => %{
        "y" => %{"field" => "y", "type" => "quantitative"}
      }
    }
  end

  @spec build_graduation_threshold_layer() :: map()
  defp build_graduation_threshold_layer do
    %{
      "mark" => %{
        "type" => "rule",
        "stroke" => "#00ff00",
        "strokeWidth" => 2,
        "strokeDash" => [5, 5]
      },
      "data" => %{"values" => [%{"y" => @graduation_threshold}]},
      "encoding" => %{
        "y" => %{"field" => "y", "type" => "quantitative"}
      }
    }
  end

  @spec build_line_layer([timeline_point()]) :: map()
  defp build_line_layer(_timeline_data) do
    %{
      "mark" => %{
        "type" => "line",
        "opacity" => 0.7,
        "strokeWidth" => 2
      },
      "encoding" => %{
        "x" => %{
          "field" => "cycle",
          "type" => "quantitative",
          "title" => "Cycle",
          "scale" => %{"domain" => [0, nil]}
        },
        "y" => %{
          "field" => "support",
          "type" => "quantitative",
          "title" => "Support Strength",
          "scale" => %{"domain" => [0.0, 1.0]}
        },
        "order" => %{"field" => "cycle", "type" => "ordinal"}
      }
    }
  end

  @spec build_point_layer([timeline_point()]) :: map()
  defp build_point_layer(_timeline_data) do
    %{
      "mark" => %{
        "type" => "circle",
        "opacity" => 0.8,
        "tooltip" => true,
        "size" => 80
      },
      "encoding" => %{
        "x" => %{
          "field" => "cycle",
          "type" => "quantitative",
          "title" => "Cycle",
          "scale" => %{"domain" => [0, nil]}
        },
        "y" => %{
          "field" => "support",
          "type" => "quantitative",
          "title" => "Support Strength",
          "scale" => %{"domain" => [0.0, 1.0]}
        },
        "color" => %{
          "field" => "support",
          "type" => "quantitative",
          "scale" => %{
            "domain" => [@death_threshold, @graduation_threshold],
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
      }
    }
  end

  @spec build_event_annotations_layer([event_annotation()]) :: map()
  defp build_event_annotations_layer([]) do
    %{
      "mark" => %{"type" => "text", "opacity" => 0},
      "encoding" => %{},
      "data" => %{"values" => []}
    }
  end

  defp build_event_annotations_layer(annotations) do
    data =
      Enum.map(annotations, fn %{cycle: cycle, label: label} ->
        %{x: cycle, y: 0.95, text: label}
      end)

    %{
      "mark" => %{
        "type" => "text",
        "fontWeight" => "bold",
        "fontSize" => 14,
        "angle" => -45,
        "align" => "left"
      },
      "encoding" => %{
        "x" => %{"field" => "x", "type" => "quantitative"},
        "y" => %{"field" => "y", "type" => "quantitative"},
        "text" => %{"field" => "text", "type" => "nominal"}
      },
      "data" => %{"values" => data}
    }
  end
end
