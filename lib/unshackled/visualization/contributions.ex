defmodule Unshackled.Visualization.Contributions do
  @moduledoc """
  Agent contribution pie chart visualization using VegaLite spec format.

  This module provides visualization data for agent contributions by role.

  Visualizations include:
  - Pie chart showing accepted contributions by agent role (percentage)
  - Secondary bar chart showing net confidence delta by agent role
  - Empty chart with message when no contributions exist
  """

  import Ecto.Query

  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Repo

  @type agent_contribution_data :: %{
          agent_role: String.t(),
          count: non_neg_integer(),
          percentage: float(),
          net_delta: float()
        }

  @doc """
  Creates a pie chart visualization of agent contributions for a blackboard session.

  ## Parameters

  - blackboard_id: The ID of the blackboard session

  ## Returns

  - VegaLite spec map on success
  - {:error, reason} on failure

  ## Examples

      iex> {:ok, spec} = Contributions.plot_agent_pie(1)

      iex> Contributions.plot_agent_pie(999)
      {:ok, %{
        "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
        "mark" => "text",
        "encoding" => %{"text" => %{"field" => "label"}},
        "data" => %{"values" => [%{"label" => "No contributions data"}]}
      }}

  """
  @spec plot_agent_pie(integer()) :: {:ok, map()} | {:error, String.t()}
  def plot_agent_pie(blackboard_id) when is_integer(blackboard_id) and blackboard_id > 0 do
    with {:ok, contributions} <- query_contributions(blackboard_id),
         {:ok, contribution_data} <- aggregate_contributions(contributions) do
      if length(contribution_data) == 0 do
        empty_spec()
      else
        spec = build_vegalite_spec(contribution_data)
        {:ok, spec}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def plot_agent_pie(_) do
    {:error, "blackboard_id must be a positive integer"}
  end

  @spec query_contributions(integer()) :: {:ok, [AgentContribution.t()]} | {:error, String.t()}
  defp query_contributions(blackboard_id) do
    try do
      query =
        from(c in AgentContribution,
          where: c.blackboard_id == ^blackboard_id,
          select: c
        )

      contributions = Repo.all(query)
      {:ok, contributions}
    rescue
      e -> {:error, "Failed to query contributions: #{inspect(e)}"}
    end
  end

  @spec aggregate_contributions([AgentContribution.t()]) ::
          {:ok, [agent_contribution_data()]} | {:error, String.t()}
  defp aggregate_contributions(contributions) do
    accepted_contributions = Enum.filter(contributions, & &1.accepted)

    if length(accepted_contributions) == 0 do
      {:ok, []}
    else
      total_accepted = length(accepted_contributions)

      data =
        accepted_contributions
        |> Enum.group_by(& &1.agent_role)
        |> Enum.map(fn {agent_role, role_contributions} ->
          count = length(role_contributions)
          percentage = count / total_accepted * 100
          net_delta = calculate_net_delta(role_contributions)

          %{
            agent_role: agent_role,
            count: count,
            percentage: Float.round(percentage, 1),
            net_delta: Float.round(net_delta, 3)
          }
        end)
        |> Enum.sort_by(&{-&1.count, &1.agent_role})

      {:ok, data}
    end
  end

  @spec calculate_net_delta([AgentContribution.t()]) :: float()
  defp calculate_net_delta(contributions) do
    Enum.reduce(contributions, 0.0, fn contribution, acc ->
      delta = contribution.support_delta || 0.0
      acc + delta
    end)
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
          %{"text" => "No contributions data", "x" => 400, "y" => 300, "fontSize" => 20}
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

  @spec build_vegalite_spec([agent_contribution_data()]) :: map()
  defp build_vegalite_spec(contribution_data) do
    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "width" => 1200,
      "height" => 500,
      "title" => %{"text" => "Agent Contributions", "fontSize" => 16},
      "resolve" => %{"scale" => %{"color" => "independent"}},
      "concat" => [
        build_pie_chart_spec(contribution_data),
        build_bar_chart_spec(contribution_data)
      ]
    }
  end

  @spec build_pie_chart_spec([agent_contribution_data()]) :: map()
  defp build_pie_chart_spec(contribution_data) do
    %{
      "title" => %{"text" => "Accepted Contributions by Role", "fontSize" => 14},
      "data" => %{"values" => contribution_data},
      "mark" => %{
        "type" => "arc",
        "outerRadius" => 180,
        "innerRadius" => 60,
        "tooltip" => true
      },
      "encoding" => %{
        "theta" => %{
          "field" => "percentage",
          "type" => "quantitative",
          "stack" => true
        },
        "color" => %{
          "field" => "agent_role",
          "type" => "nominal",
          "legend" => %{"title" => "Agent Role"},
          "scale" => %{
            "domain" => Enum.map(contribution_data, & &1.agent_role),
            "range" => color_palette(length(contribution_data))
          }
        },
        "tooltip" => [
          %{"field" => "agent_role", "type" => "nominal", "title" => "Agent Role"},
          %{
            "field" => "count",
            "type" => "quantitative",
            "title" => "Count"
          },
          %{
            "field" => "percentage",
            "type" => "quantitative",
            "title" => "Percentage",
            "format" => ".1f"
          }
        ]
      }
    }
  end

  @spec build_bar_chart_spec([agent_contribution_data()]) :: map()
  defp build_bar_chart_spec(contribution_data) do
    %{
      "title" => %{"text" => "Net Confidence Delta by Role", "fontSize" => 14},
      "data" => %{"values" => contribution_data},
      "mark" => %{
        "type" => "bar",
        "tooltip" => true
      },
      "encoding" => %{
        "x" => %{
          "field" => "agent_role",
          "type" => "nominal",
          "title" => "Agent Role",
          "sort" => %{"field" => "count", "order" => "descending"}
        },
        "y" => %{
          "field" => "net_delta",
          "type" => "quantitative",
          "title" => "Net Confidence Delta"
        },
        "color" => %{
          "field" => "agent_role",
          "type" => "nominal",
          "legend" => nil,
          "scale" => %{
            "domain" => Enum.map(contribution_data, & &1.agent_role),
            "range" => color_palette(length(contribution_data))
          }
        },
        "tooltip" => [
          %{"field" => "agent_role", "type" => "nominal", "title" => "Agent Role"},
          %{
            "field" => "net_delta",
            "type" => "quantitative",
            "title" => "Net Delta",
            "format" => ".3f"
          },
          %{
            "field" => "count",
            "type" => "quantitative",
            "title" => "Count"
          }
        ]
      }
    }
  end

  @default_colors [
    "#4e79a7",
    "#f28e2b",
    "#e15759",
    "#76b7b2",
    "#59a14f",
    "#edc948",
    "#b07aa1",
    "#ff9da7",
    "#9c755f",
    "#bab0ac",
    "#d37295",
    "#8b6f9c",
    "#5b4b4b",
    "#4b7db2",
    "#6c8ebf"
  ]

  @spec color_palette(non_neg_integer()) :: [String.t()]
  defp color_palette(count) when count <= 0, do: []
  defp color_palette(count), do: Enum.take(@default_colors, count)
end
