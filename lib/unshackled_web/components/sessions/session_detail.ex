defmodule UnshackledWeb.Components.Sessions.SessionDetail do
  @moduledoc """
  Session detail page layout component.

  This component renders the complete session detail page with all
  sections including claim card, timeline, metrics, cost breakdown,
  charts, and cycle log.
  """
  use UnshackledWeb, :html

  alias UnshackledWeb.CoreComponents
  alias UnshackledWeb.Components.Sessions.ClaimCard
  alias UnshackledWeb.Components.Sessions.EvolutionTimeline
  alias UnshackledWeb.Components.Sessions.CycleLog
  alias UnshackledWeb.Components.Sessions.CostCard
  alias UnshackledWeb.Components.Sessions.SessionControls
  alias UnshackledWeb.Components.Sessions.ClaimsLists

  import UnshackledWeb.SessionsLive.Show.Formatters,
    only: [
      format_support: 1,
      support_color: 1,
      status_text: 1,
      status_text_color: 1,
      status_border_class: 1
    ]

  attr(:blackboard, :map, required: true)
  attr(:session_id, :string, required: true)
  attr(:status, :atom, required: true)
  attr(:show_stop_confirm, :boolean, required: true)
  attr(:show_delete_confirm, :boolean, required: true)
  attr(:support_timeline, :list, required: true)
  attr(:contributions_data, :list, required: true)
  attr(:trajectory_data, :map, required: true)
  attr(:trajectory_loading, :boolean, default: false)
  attr(:cemetery_entries, :list, required: true)
  attr(:graduated_claims, :list, required: true)
  attr(:cycle_log, :list, required: true)
  attr(:has_more_cycles, :boolean, required: true)
  attr(:new_cycle_number, :integer, default: nil)
  attr(:claim_summary, :map, default: nil)
  attr(:claim_transitions, :list, default: [])
  attr(:expanded_timeline_nodes, :map, default: %{})
  attr(:expanded_summary_sections, :map, default: MapSet.new())
  attr(:total_cost, :float, default: 0.0)
  attr(:cost_by_cycle, :list, default: [])
  attr(:cost_by_agent, :list, default: [])

  def session_detail(assigns) do
    ~H"""
    <div class={["space-y-6", "border-l-4", status_border_class(@status)]}>
      <.breadcrumb>
        <:item navigate="/sessions">Sessions</:item>
        <:item>Session #<%= @blackboard.id %></:item>
      </.breadcrumb>

      <.header>
        Session <%= @blackboard.id %>
        <:subtitle>
          <div class="flex items-center gap-3">
            <.status_badge status={@status} />
            <span class="text-text-muted">Cycle <%= @blackboard.cycle_count %></span>
          </div>
        </:subtitle>
        <:actions>
           <SessionControls.session_controls
             session_id={@session_id}
             status={@status}
             blackboard_id={@blackboard.id}
             show_stop_confirm={@show_stop_confirm}
             show_delete_confirm={@show_delete_confirm}
           />
           <a href="/sessions">
             <.button variant={:secondary}>Back to Sessions</.button>
           </a>
         </:actions>
      </.header>

      <%!-- Contextualized Claim Card --%>
      <ClaimCard.contextualized_claim_card
        current_claim={@blackboard.current_claim}
        claim_summary={@claim_summary}
        expanded_summary_sections={@expanded_summary_sections}
      />

      <%!-- Claim Evolution Timeline --%>
      <EvolutionTimeline.claim_evolution_timeline
        blackboard={@blackboard}
        claim_transitions={@claim_transitions}
        claim_summary={@claim_summary}
        expanded_nodes={@expanded_timeline_nodes}
      />

      <%!-- Key Metrics --%>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <.simple_metric_card
          label="Support Strength"
          value={format_support(@blackboard.support_strength)}
          color={support_color(@blackboard.support_strength)}
        />
        <.simple_metric_card
          label="Cycle Count"
          value={@blackboard.cycle_count}
          color="text-text-primary"
        />
        <.simple_metric_card
          label="Status"
          value={status_text(@status)}
          color={status_text_color(@status)}
        />
      </div>

      <%!-- Cost Display Card --%>
      <CostCard.cost_card
        total_cost={@total_cost}
        cost_limit={@blackboard.cost_limit_usd}
      />

      <%!-- Cost Breakdown by Cycle (collapsible) --%>
      <CoreComponents.collapsible_section
        id="cost-by-cycle"
        count={length(@cost_by_cycle)}
        expanded={false}
      >
        <:title>Cost by Cycle</:title>
        <CostCard.cost_by_cycle_list costs={@cost_by_cycle} />
      </CoreComponents.collapsible_section>

      <%!-- Cost Breakdown by Agent (collapsible) --%>
      <CoreComponents.collapsible_section
        id="cost-by-agent"
        count={length(@cost_by_agent)}
        expanded={false}
      >
        <:title>Cost by Agent</:title>
        <CostCard.cost_by_agent_list costs={@cost_by_agent} />
      </CoreComponents.collapsible_section>

      <%!-- Charts Grid --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <%!-- Support Timeline Chart --%>
        <.card>
          <h2 class="text-lg font-bold text-text-primary mb-4 uppercase tracking-wider">
            Support Timeline
          </h2>
          <.chart
            id={"support-timeline-#{@blackboard.id}"}
            hook="SupportTimelineHook"
            data={%{support_timeline: @support_timeline, claim_transitions: @claim_transitions}}
            height={300}
            margin_right={50}
          />
        </.card>

        <%!-- Agent Contributions Pie Chart --%>
        <.card>
          <h2 class="text-lg font-bold text-text-primary mb-4 uppercase tracking-wider">
            Agent Contributions
          </h2>
          <.chart
            id={"contributions-pie-#{@blackboard.id}"}
            hook="ContributionsPieHook"
            data={@contributions_data}
            height={300}
            margin_bottom={20}
          />
        </.card>
      </div>

        <%!-- Trajectory Plot - Full Width (3D) --%>
        <.card>
          <h2 class="text-lg font-bold text-text-primary mb-4 uppercase tracking-wider">
            Embedding Trajectory (3D t-SNE)
          </h2>
          <%= if @trajectory_loading do %>
            <div class="flex items-center justify-center h-[450px] bg-surface-elevated">
              <div class="text-center">
                <div class="animate-spin h-8 w-8 border-2 border-accent border-t-transparent rounded-full mx-auto mb-3"></div>
                <p class="text-text-muted text-sm">Computing trajectory visualization...</p>
              </div>
            </div>
          <% else %>
            <.chart
              id={"trajectory-3d-plot-#{@blackboard.id}"}
              hook="Trajectory3DPlotHook"
              data={@trajectory_data}
              height={450}
            />
          <% end %>
        </.card>

      <%!-- Cycle Log --%>
      <.card>
        <h2 class="text-lg font-bold text-text-primary mb-4 uppercase tracking-wider">
          Cycle Log
        </h2>
        <CycleLog.cycle_log_view cycle_log={@cycle_log} has_more_cycles={@has_more_cycles} new_cycle_number={@new_cycle_number} />
      </.card>

      <%!-- Active Objection --%>
      <%= if @blackboard.active_objection do %>
        <.card>
          <h2 class="text-lg font-bold text-status-paused mb-4 uppercase tracking-wider">
            Active Objection
          </h2>
          <p class="text-text-secondary leading-relaxed">
            <%= @blackboard.active_objection %>
          </p>
        </.card>
      <% end %>

      <%!-- Analogy of Record --%>
      <%= if @blackboard.analogy_of_record do %>
        <.card>
          <h2 class="text-lg font-bold text-status-graduated mb-4 uppercase tracking-wider">
            Analogy of Record
          </h2>
          <p class="text-text-secondary leading-relaxed">
            <%= @blackboard.analogy_of_record %>
          </p>
        </.card>
      <% end %>

      <%!-- Cemetery Section (collapsible) --%>
      <%= if @cemetery_entries != [] do %>
        <.collapsible id="cemetery" title="Cemetery" count={length(@cemetery_entries)}>
          <ClaimsLists.cemetery_list entries={@cemetery_entries} />
        </.collapsible>
      <% end %>

      <%!-- Graduated Claims Section (collapsible) --%>
      <%= if @graduated_claims != [] do %>
        <.collapsible id="graduated" title="Graduated" count={length(@graduated_claims)}>
          <ClaimsLists.graduated_list claims={@graduated_claims} />
        </.collapsible>
      <% end %>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:color, :string, default: "text-text-primary")

  def simple_metric_card(assigns) do
    ~H"""
    <.card class="text-center">
      <p class="text-xs font-bold uppercase tracking-wider text-text-muted mb-2">
        <%= @label %>
      </p>
      <p class={["text-3xl font-mono-data", @color]}>
        <%= @value %>
      </p>
    </.card>
    """
  end
end
