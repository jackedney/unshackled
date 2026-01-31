defmodule UnshackledWeb.SessionsLive.Show.Formatters do
  @moduledoc """
  Pure formatting utility functions for displaying session data.

  This module contains all display formatting functions extracted from
  the SessionsLive.Show module. All functions are pure transformations
  with no side effects or socket access.

  ## Examples

      iex> Formatters.delta_color(0.5)
      "text-status-active"

      iex> Formatters.format_agent_role("steelman")
      "Steelman"

      iex> Formatters.format_cost(1.2345)
      "$1.2345"
  """

  @status_styles %{
    running: %{text: "Running", color: "text-status-active", border: "border-l-status-active"},
    active: %{text: "Active", color: "text-status-active", border: "border-l-status-active"},
    paused: %{text: "Paused", color: "text-status-paused", border: "border-l-status-paused"},
    stopped: %{text: "Stopped", color: "text-status-dead", border: "border-l-status-dead"},
    completed: %{
      text: "Completed",
      color: "text-status-graduated",
      border: "border-l-status-graduated"
    },
    graduated: %{
      text: "Graduated",
      color: "text-status-graduated",
      border: "border-l-status-graduated"
    },
    dead: %{text: "Dead", color: "text-status-dead", border: "border-l-status-dead"}
  }

  @default_status_style %{text: "Unknown", color: "text-text-muted", border: "border-border"}

  @doc """
  Returns the color class for a delta value.

  ## Examples

      iex> Formatters.delta_color(0.5)
      "text-status-active"

      iex> Formatters.delta_color(-0.3)
      "text-status-dead"

      iex> Formatters.delta_color(nil)
      "text-text-muted"

      iex> Formatters.delta_color(0)
      "text-text-muted"
  """
  def delta_color(nil), do: "text-text-muted"
  def delta_color(delta) when delta > 0, do: "text-status-active"
  def delta_color(delta) when delta < 0, do: "text-status-dead"
  def delta_color(_delta), do: "text-text-muted"

  @doc """
  Formats a delta value as a string with sign.

  ## Examples

      iex> Formatters.format_delta(0.5)
      "+0.5"

      iex> Formatters.format_delta(-0.3)
      "-0.3"

      iex> Formatters.format_delta(nil)
      "—"

      iex> Formatters.format_delta(0)
      "0.0"
  """
  def format_delta(nil), do: "—"
  def format_delta(delta) when delta > 0, do: "+#{Float.round(delta, 3)}"
  def format_delta(delta) when delta < 0, do: "#{Float.round(delta, 3)}"
  def format_delta(_delta), do: "0.0"

  @doc """
  Formats an agent role by capitalizing and replacing underscores.

  ## Examples

      iex> Formatters.format_agent_role("steelman")
      "Steelman"

      iex> Formatters.format_agent_role("boundary_hunter")
      "Boundary Hunter"
  """
  def format_agent_role(role) do
    role
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Returns the background color class for an agent role.

  ## Examples

      iex> Formatters.agent_role_color("explorer")
      "bg-[#22c55e]"

      iex> Formatters.agent_role_color("unknown")
      "bg-gray-400"
  """
  def agent_role_color(role) do
    case Unshackled.Agents.Metadata.bg_class(role) do
      nil -> "bg-gray-400"
      bg_class -> bg_class
    end
  end

  @doc """
  Returns the color class for a support delta between two cycles.

  ## Examples

      iex> Formatters.support_delta_color(1, 0.5, 0.7)
      "text-status-active"
  """
  def support_delta_color(blackboard_id, from_cycle, to_cycle) do
    from_support =
      UnshackledWeb.SessionsLive.Show.DataLoader.get_support_at_cycle(
        blackboard_id,
        from_cycle
      )

    to_support =
      UnshackledWeb.SessionsLive.Show.DataLoader.get_support_at_cycle(
        blackboard_id,
        to_cycle
      )

    case {from_support, to_support} do
      {nil, _} -> "text-text-muted"
      {_, nil} -> "text-text-muted"
      {from, to} when to > from -> "text-status-active"
      {from, to} when to < from -> "text-status-dead"
      _ -> "text-text-muted"
    end
  end

  @doc """
  Formats a support delta between two cycles.

  ## Examples

      iex> Formatters.format_support_delta(1, 0.5, 0.7)
      "+20.0%"
  """
  def format_support_delta(blackboard_id, from_cycle, to_cycle) do
    from_support =
      UnshackledWeb.SessionsLive.Show.DataLoader.get_support_at_cycle(
        blackboard_id,
        from_cycle
      )

    to_support =
      UnshackledWeb.SessionsLive.Show.DataLoader.get_support_at_cycle(
        blackboard_id,
        to_cycle
      )

    case {from_support, to_support} do
      {nil, nil} ->
        "N/A"

      {nil, support} ->
        format_delta_value(support, true)

      {support, nil} ->
        format_delta_value(support, false)

      {from, to} ->
        delta = to - from
        format_delta_value(delta, true)
    end
  end

  @doc """
  Formats a support value as a percentage.

  ## Examples

      iex> Formatters.format_support(nil)
      "—"

      iex> Formatters.format_support(0.5)
      "50.0%"
  """
  def format_support(nil), do: "—"
  def format_support(support), do: "#{Float.round(support * 100, 1)}%"

  @doc """
  Returns the color class for a support value.

  ## Examples

      iex> Formatters.support_color(0.8)
      "text-status-active"

      iex> Formatters.support_color(0.5)
      "text-status-paused"

      iex> Formatters.support_color(0.2)
      "text-status-dead"
  """
  def support_color(nil), do: "text-text-muted"
  def support_color(support) when support >= 0.7, do: "text-status-active"
  def support_color(support) when support >= 0.4, do: "text-status-paused"
  def support_color(_support), do: "text-status-dead"

  @doc """
  Formats a change type for display.

  ## Examples

      iex> Formatters.format_change_type("refinement")
      "Refined"

      iex> Formatters.format_change_type("unknown")
      "Changed"
  """
  def format_change_type("refinement"), do: "Refined"
  def format_change_type("pivot"), do: "Pivoted"
  def format_change_type("expansion"), do: "Expanded"
  def format_change_type("contraction"), do: "Contracted"
  def format_change_type(_), do: "Changed"

  @doc """
  Returns the badge styles for a transition change type.

  ## Examples

      iex> Formatters.transition_badge_styles("refinement")
      "border-status-active/50 text-status-active"
  """
  def transition_badge_styles("refinement"), do: "border-status-active/50 text-status-active"
  def transition_badge_styles("pivot"), do: "border-status-paused/50 text-status-paused"
  def transition_badge_styles("expansion"), do: "border-status-graduated/50 text-status-graduated"
  def transition_badge_styles("contraction"), do: "border-status-dead/50 text-status-dead"
  def transition_badge_styles(_), do: "border-border text-text-muted"

  @doc """
  Formats a cost value as a dollar amount.

  ## Examples

      iex> Formatters.format_cost(1.2345)
      "$1.2345"
  """
  def format_cost(cost) when is_number(cost) do
    :erlang.float_to_binary(cost, decimals: 4)
    |> (&"$#{&1}").()
  end

  @doc """
  Formats a cost limit for display.

  ## Examples

      iex> Formatters.format_cost_limit(nil)
      "No limit"

      iex> Formatters.format_cost_limit(%Decimal{coeff: 1000})
      "$10.00"

      iex> Formatters.format_cost_limit(10.0)
      "$10.0"
  """
  def format_cost_limit(nil), do: "No limit"

  def format_cost_limit(%Decimal{} = limit) do
    "$#{Decimal.to_string(limit)}"
  end

  def format_cost_limit(limit) when is_number(limit) do
    "$#{limit}"
  end

  @doc """
  Calculates the percentage of a cost limit used.

  ## Examples

      iex> Formatters.calculate_limit_percentage(5.0, nil)
      "0%"

      iex> Formatters.calculate_limit_percentage(5.0, %Decimal{coeff: 1000})
      "50.0%"
  """
  def calculate_limit_percentage(_total_cost, nil), do: "0%"

  def calculate_limit_percentage(total_cost, limit) do
    limit_float = Decimal.to_float(limit)
    percentage = total_cost / limit_float * 100
    "#{Float.round(percentage, 1)}%"
  end

  @doc """
  Returns the color class for a cost limit based on usage percentage.

  ## Examples

      iex> Formatters.limit_color(50.0, nil)
      "bg-status-active"

      iex> Formatters.limit_color(85.0, %Decimal{coeff: 1000})
      "bg-status-paused"

      iex> Formatters.limit_color(105.0, %Decimal{coeff: 1000})
      "bg-status-dead"
  """
  def limit_color(_total_cost, nil), do: "bg-status-active"

  def limit_color(total_cost, limit) do
    limit_float = Decimal.to_float(limit)
    percentage = total_cost / limit_float * 100

    cond do
      percentage >= 100 -> "bg-status-dead"
      percentage >= 80 -> "bg-status-paused"
      true -> "bg-status-active"
    end
  end

  @doc """
  Calculates an agent's cost as a percentage of total costs.

  ## Examples

      iex> Formatters.calculate_agent_cost_percentage(5.0, [])
      "0%"

      iex> Formatters.calculate_agent_cost_percentage(5.0, [%{total_cost: 10.0}])
      "50.0%"
  """
  def calculate_agent_cost_percentage(_agent_cost, []) do
    "0%"
  end

  def calculate_agent_cost_percentage(agent_cost, all_costs) do
    total_cost = Enum.reduce(all_costs, 0.0, fn c, acc -> acc + c.total_cost end)

    if total_cost > 0 do
      percentage = agent_cost / total_cost * 100
      "#{Float.round(percentage, 1)}%"
    else
      "0%"
    end
  end

  @doc """
  Returns the status text for a given status atom.

  ## Examples

      iex> Formatters.status_text(:running)
      "Running"

      iex> Formatters.status_text(:unknown)
      "Unknown"
  """
  def status_text(status), do: Map.get(@status_styles, status, @default_status_style).text

  @doc """
  Returns the status text color class for a given status atom.

  ## Examples

      iex> Formatters.status_text_color(:running)
      "text-status-active"
  """
  def status_text_color(status),
    do: Map.get(@status_styles, status, @default_status_style).color

  @doc """
  Returns the status border class for a given status atom.

  ## Examples

      iex> Formatters.status_border_class(:running)
      "border-l-status-active"
  """
  def status_border_class(status),
    do: Map.get(@status_styles, status, @default_status_style).border

  defp format_delta_value(nil, _is_positive), do: "N/A"
  defp format_delta_value(delta, true) when delta > 0, do: "+#{Float.round(delta * 100, 1)}%"
  defp format_delta_value(delta, _), do: "#{Float.round(delta * 100, 1)}%"

  @doc """
  Truncates a contribution text to a maximum length.

  ## Examples

      iex> Formatters.truncate_contribution("This is a long text", 10)
      "This is a ..."

      iex> Formatters.truncate_contribution("Short", 10)
      "Short"

      iex> Formatters.truncate_contribution(nil, 10)
      ""
  """
  def truncate_contribution(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  def truncate_contribution(_, _), do: ""
end
