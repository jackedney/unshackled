defmodule UnshackledWeb.Components.Sessions.CycleLog do
  @moduledoc """
  Component for displaying cycle log with expandable contributions.

  Renders paginated cycle entries grouped by time period (last hour, earlier today,
  older) with expandable contribution details. Supports load more pagination and
  highlights new cycles as they appear.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias UnshackledWeb.CoreComponents

  import UnshackledWeb.CoreComponents, only: [button: 1]

  import UnshackledWeb.SessionsLive.Show.Formatters,
    only: [
      delta_color: 1,
      format_delta: 1,
      format_agent_role: 1,
      agent_role_color: 1
    ]

  @doc """
  Renders the cycle log view with pagination support.

  ## Attributes

  * `cycle_log` - List of cycle entries (required)
  * `has_more_cycles` - Whether more cycles can be loaded (required)
  * `new_cycle_number` - Cycle number to highlight as new (optional)

  ## Examples

      <.cycle_log_view
        cycle_log={@cycle_log}
        has_more_cycles={@has_more_cycles}
        new_cycle_number={@new_cycle_number}
      />
  """
  attr(:cycle_log, :list, required: true, doc: "list of cycle entries")
  attr(:has_more_cycles, :boolean, required: true, doc: "whether more cycles can be loaded")
  attr(:new_cycle_number, :integer, default: nil, doc: "cycle number to highlight as new")

  def cycle_log_view(assigns) do
    ~H"""
    <div
      id="cycle-log-container"
      class="space-y-4"
      phx-hook="CycleLogHook"
      data-new-cycle-number={@new_cycle_number}
    >
      <%= if @cycle_log == [] do %>
        <p class="text-text-muted text-sm italic">Waiting for first cycle...</p>
      <% else %>
        <.render_cycle_groups cycle_log={@cycle_log} has_more_cycles={@has_more_cycles} new_cycle_number={@new_cycle_number} />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders cycle entries grouped by time period.

  ## Attributes

  * `cycle_log` - List of cycle entries (required)
  * `has_more_cycles` - Whether more cycles can be loaded (required)
  * `new_cycle_number` - Cycle number to highlight as new (optional)

  ## Examples

      <.render_cycle_groups
        cycle_log={@cycle_log}
        has_more_cycles={@has_more_cycles}
        new_cycle_number={@new_cycle_number}
      />
  """
  attr(:cycle_log, :list, required: true, doc: "list of cycle entries")
  attr(:has_more_cycles, :boolean, required: true, doc: "whether more cycles can be loaded")
  attr(:new_cycle_number, :integer, default: nil, doc: "cycle number to highlight as new")

  def render_cycle_groups(assigns) do
    ~H"""
    <%= for group <- group_cycles_by_time(@cycle_log) do %>
      <CoreComponents.collapsible_section
        id={"cycles-#{group.period}"}
        count={group.count}
        expanded={group.expanded}
      >
        <:title><%= group.label %></:title>
        <div class="space-y-3">
          <%= for cycle <- group.cycles do %>
            <.cycle_entry cycle={cycle} new_cycle_number={@new_cycle_number} />
          <% end %>
        </div>
      </CoreComponents.collapsible_section>
    <% end %>

    <%= if @has_more_cycles do %>
      <div class="pt-4 border-t border-border-subtle">
        <.button phx-click="load_more_cycles" variant={:secondary} class="w-full">
          Load more
        </.button>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders a single cycle entry with its contributions.

  ## Attributes

  * `cycle` - Cycle map containing cycle_number, total_delta, and contributions (required)
  * `new_cycle_number` - Cycle number to highlight as new (optional)

  ## Examples

      <.cycle_entry
        cycle={cycle}
        new_cycle_number={@new_cycle_number}
      />
  """
  attr(:cycle, :map, required: true, doc: "cycle map containing cycle data")
  attr(:new_cycle_number, :integer, default: nil, doc: "cycle number to highlight as new")

  def cycle_entry(assigns) do
    is_new = assigns[:new_cycle_number] == assigns[:cycle].cycle_number

    assigns = assign(assigns, :is_new, is_new)

    ~H"""
    <div
      class={[
        "border-l-2 border-border-strong pl-4 py-3 relative",
        @is_new && "cycle-new"
      ]}
      id={"cycle-#{@cycle.cycle_number}"}
      phx-hook={@is_new && "CycleNewHook"}
    >
      <%!-- Cycle number badge --%>
      <div class="absolute -left-[10px] top-3 w-6 h-6 bg-surface border-2 border-border-strong flex items-center justify-center">
        <div class="w-2 h-2 bg-text-muted"></div>
      </div>

      <div class="flex items-start justify-between gap-4 mb-3">
        <span class="text-sm font-bold text-text-primary uppercase tracking-wider font-mono-data">
          Cycle <%= @cycle.cycle_number %>
        </span>
        <span class={[
          "text-sm font-mono-data font-bold",
          delta_color(@cycle.total_delta)
        ]}>
          <%= format_delta(@cycle.total_delta) %>
        </span>
      </div>

      <%!-- Agent contributions for this cycle --%>
      <div class="space-y-2">
        <%= for contribution <- @cycle.contributions do %>
          <.contribution_item contribution={contribution} cycle={@cycle} />
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single agent contribution within a cycle.

  ## Attributes

  * `contribution` - Contribution map containing agent_role, support_delta, accepted, and output_text (required)
  * `cycle` - Cycle map for context (required)

  ## Examples

      <.contribution_item
        contribution={contribution}
        cycle={cycle}
      />
  """
  attr(:contribution, :map, required: true, doc: "contribution map")
  attr(:cycle, :map, required: true, doc: "cycle map for context")

  def contribution_item(assigns) do
    ~H"""
    <div class="flex items-start gap-3 text-sm">
      <%!-- Agent role dot --%>
      <div class={[
        "w-3 h-3 flex-shrink-0 mt-0.5",
        agent_role_color(@contribution.agent_role)
      ]}>
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-text-secondary capitalize">
            <%= format_agent_role(@contribution.agent_role) %>
          </span>
          <span class={[
            "font-mono-data text-xs",
            delta_color(@contribution.support_delta)
          ]}>
            <%= format_delta(@contribution.support_delta) %>
          </span>
          <%= if @contribution.accepted do %>
            <span class="text-status-active text-xs" title="Accepted">✓</span>
          <% else %>
            <span class="text-status-dead text-xs" title="Rejected">✗</span>
          <% end %>
        </div>

        <%!-- Expandable contribution text --%>
        <button
          type="button"
          class="text-text-muted text-xs hover:text-text-primary transition-colors"
          phx-click={toggle_contribution("contribution-text-#{@contribution.agent_role}-#{@cycle.cycle_number}")}
          aria-expanded="false"
          aria-controls={"contribution-text-#{@contribution.agent_role}-#{@cycle.cycle_number}"}
        >
          Show contribution
        </button>

        <div
          id={"contribution-text-#{@contribution.agent_role}-#{@cycle.cycle_number}"}
          class="mt-2 p-3 bg-surface-elevated border border-border text-sm text-text-secondary hidden"
        >
          <%= @contribution.output_text || "No contribution text available" %>
        </div>
      </div>
     </div>
    """
  end

  @doc """
  Returns a JS command for toggling contribution visibility.

  ## Examples

      toggle_contribution("contribution-text-explorer-1")
  """
  def toggle_contribution(selector) do
    %JS{}
    |> JS.toggle(
      to: "##{selector}",
      time: 0,
      in: {"", "", ""},
      out: {"", "", ""}
    )
  end

  @doc """
  Groups cycles by time period for better organization.

  Returns a list of groups with labels like "Last hour", "Earlier today", "Older".

  ## Examples

      iex> cycles = [%{inserted_at: ~U[2025-02-07 20:30:00Z], cycle_number: 1}]
      iex> CycleLog.group_cycles_by_time(cycles)
      [%{label: "Last hour", period: "last-hour", cycles: [...], count: 1, expanded: true}]
  """
  def group_cycles_by_time([]), do: []

  def group_cycles_by_time(cycles) do
    now = DateTime.utc_now()

    grouped =
      Enum.group_by(cycles, fn cycle ->
        case cycle do
          %{inserted_at: inserted_at} ->
            case parse_datetime(inserted_at) do
              nil -> :older
              dt -> classify_by_age(DateTime.diff(now, dt))
            end

          _ ->
            :older
        end
      end)

    [
      maybe_group(grouped[:last_hour], "Last hour", "last-hour", true),
      maybe_group(grouped[:earlier_today], "Earlier today", "earlier-today", false),
      maybe_group(grouped[:older], "Older", "older", false)
    ]
    |> List.flatten()
  end

  @doc """
  Classifies a time difference in seconds into a period.

  ## Examples

      iex> CycleLog.classify_by_age(1800)
      :last_hour

      iex> CycleLog.classify_by_age(40000)
      :earlier_today

      iex> CycleLog.classify_by_age(200000)
      :older
  """
  def classify_by_age(diff) when diff < 3600, do: :last_hour
  def classify_by_age(diff) when diff < 86_400, do: :earlier_today
  def classify_by_age(_), do: :older

  @doc """
  Builds a group map if cycles exist, otherwise returns empty list.

  ## Examples

      iex> cycles = [%{cycle_number: 1}]
      iex> CycleLog.maybe_group(cycles, "Test", "test", true)
      [%{label: "Test", period: "test", cycles: [...], count: 1, expanded: true}]

      iex> CycleLog.maybe_group([], "Test", "test", true)
      []
  """
  def maybe_group(nil, _, _, _), do: []
  def maybe_group([], _, _, _), do: []

  def maybe_group(cycles, label, period, expanded) do
    [%{label: label, period: period, cycles: cycles, count: length(cycles), expanded: expanded}]
  end

  @doc """
  Parses a datetime from various formats.

  ## Examples

      iex> dt = ~U[2025-02-07 20:30:00Z]
      iex> CycleLog.parse_datetime(dt)
      dt

      iex> CycleLog.parse_datetime("2025-02-07T20:30:00Z")
      ~U[2025-02-07 20:30:00Z]

      iex> CycleLog.parse_datetime(nil)
      nil
  """
  def parse_datetime(%DateTime{} = dt), do: dt

  def parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  def parse_datetime(_), do: nil
end
