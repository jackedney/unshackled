defmodule UnshackledWeb.Components.Sessions.EvolutionTimeline do
  @moduledoc """
  Component for displaying claim evolution timeline with transitions.

  Renders a vertical timeline of claim changes with expandable cards showing
  detailed diff views and contribution excerpts. Supports both desktop and
  mobile layouts with different visual presentations.
  """

  use Phoenix.Component

  import UnshackledWeb.CoreComponents, only: [card: 1]

  import UnshackledWeb.SessionsLive.Show.Formatters,
    only: [
      transition_badge_styles: 1,
      format_change_type: 1,
      format_agent_role: 1,
      support_delta_color: 3,
      format_support_delta: 3,
      truncate_contribution: 2
    ]

  import UnshackledWeb.SessionsLive.Show.DataLoader, only: [format_support_level: 2]

  @doc """
  Renders the claim evolution timeline with transitions.

  ## Attributes

  * `blackboard` - Blackboard map containing session data (required)
  * `claim_transitions` - List of claim transition records (optional, defaults to [])
  * `claim_summary` - Map containing summary data (optional)
  * `expanded_nodes` - Map of expanded timeline node IDs (optional, defaults to %{})

  ## Examples

      <.claim_evolution_timeline
        blackboard={@blackboard}
        claim_transitions={@claim_transitions}
        claim_summary={@claim_summary}
        expanded_nodes={@expanded_timeline_nodes}
      />
  """
  attr(:blackboard, :map, required: true, doc: "blackboard map containing session data")
  attr(:claim_transitions, :list, default: [], doc: "list of claim transition records")
  attr(:claim_summary, :map, default: nil, doc: "map containing summary data")
  attr(:expanded_nodes, :map, default: %{}, doc: "map of expanded timeline node IDs")

  def claim_evolution_timeline(assigns) do
    ~H"""
    <.card>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-bold text-text-primary uppercase tracking-wider">
          Claim Evolution
        </h2>
        <%= if @claim_transitions != [] do %>
          <button
            type="button"
            phx-click="toggle_all_timeline_nodes"
            class="text-xs text-text-muted hover:text-text-primary"
          >
            <%= if all_expanded?(@expanded_nodes, @claim_transitions) do %>
              Collapse All
            <% else %>
              Expand All
            <% end %>
          </button>
        <% end %>
      </div>

      <%= if @claim_transitions == [] do %>
        <div class="text-center py-8">
          <p class="text-text-secondary text-sm">
            No claim changes recorded. The claim has remained consistent.
          </p>
        </div>
      <% else %>
        <%!-- Desktop: vertical timeline with connected nodes --%>
        <div class="hidden md:block relative">
          <%!-- Vertical timeline line --%>
          <div class="absolute left-[19px] top-4 bottom-4 w-0.5 bg-border-strong"></div>

          <%= for {transition, _index} <- Enum.with_index(@claim_transitions) do %>
            <div class="relative flex items-start gap-4 pb-6">
              <%!-- Timeline node --%>
              <div class="flex flex-shrink-0 relative z-10">
                <div
                  class={[
                    "w-10 h-10 border-2 border-surface bg-surface-elevated",
                    "flex items-center justify-center font-mono-data text-xs font-bold",
                    "cursor-pointer hover:border-text-primary transition-colors",
                    "group relative"
                  ]}
                  phx-click="toggle_timeline_node"
                  phx-value-node={transition.id}
                  title="Click to expand/collapse"
                >
                  <span class="text-text-primary"><%= transition.to_cycle %></span>

                  <%!-- Hover tooltip --%>
                  <div class={[
                    "absolute left-12 top-0 w-64 p-3 bg-surface-elevated",
                    "border-2 border-border shadow-lg opacity-0 invisible",
                    "group-hover:opacity-100 group-hover:visible",
                    "transition-all z-50"
                  ]}>
                    <div class="text-xs font-bold text-text-muted mb-1">
                      Cycle <%= transition.to_cycle %>
                    </div>
                    <div class="text-sm text-text-primary leading-snug line-clamp-3">
                      <%= transition.new_claim %>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Desktop timeline content --%>
              <.timeline_card
                transition={transition}
                blackboard={@blackboard}
                expanded={Map.has_key?(@expanded_nodes, transition.id)}
                show_contribution_excerpt={true}
              />
            </div>
          <% end %>
        </div>

        <%!-- Mobile: stacked cards layout --%>
        <div class="md:hidden space-y-3">
          <%= for {transition, _index} <- Enum.with_index(@claim_transitions) do %>
            <.timeline_card
              transition={transition}
              blackboard={@blackboard}
              expanded={Map.has_key?(@expanded_nodes, transition.id)}
              show_contribution_excerpt={false}
              mobile={true}
            />
          <% end %>
        </div>
      <% end %>

      <%!-- Summary card at bottom --%>
      <%= if @claim_summary do %>
        <div class="border-t border-border-subtle pt-4 mt-4">
          <div class="flex items-start gap-3">
            <div class="flex-shrink-0 w-8 h-8 bg-status-graduated/20 border border-status-graduated/30 flex items-center justify-center">
              <span class="text-xs font-bold text-status-graduated">S</span>
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="text-sm font-bold text-text-primary mb-1">
                Context Summary
              </h3>
              <p class="text-text-secondary text-xs leading-relaxed">
                <%= @claim_summary.full_context_summary %>
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </.card>
    """
  end

  @doc """
  Renders a single timeline card for a claim transition.

  ## Attributes

  * `transition` - Transition record (required)
  * `blackboard` - Blackboard map (required)
  * `expanded` - Whether card is expanded (optional, defaults to false)
  * `show_contribution_excerpt` - Show contribution excerpt on desktop (optional, defaults to true)
  * `mobile` - Render mobile layout (optional, defaults to false)

  ## Examples

      <.timeline_card
        transition={transition}
        blackboard={@blackboard}
        expanded={Map.has_key?(@expanded_nodes, transition.id)}
        show_contribution_excerpt={true}
      />
  """
  attr(:transition, :map, required: true, doc: "transition record")
  attr(:blackboard, :map, required: true, doc: "blackboard map")
  attr(:expanded, :boolean, default: false, doc: "whether card is expanded")

  attr(:show_contribution_excerpt, :boolean,
    default: true,
    doc: "show contribution excerpt on desktop"
  )

  attr(:mobile, :boolean, default: false, doc: "render mobile layout")

  def timeline_card(assigns) do
    ~H"""
    <div
      class={[
        "flex-1 min-w-0",
        "border-2 border-border bg-surface",
        "p-4",
        "transition-all duration-150",
        "cursor-pointer",
        "hover:border-text-muted",
        "active:scale-[0.99]",
        @expanded && "border-text-primary shadow-md"
      ]}
      id={"timeline-node-#{@transition.id}"}
      phx-click="toggle_timeline_node"
      phx-value-node={@transition.id}
    >
      <%!-- Card header: cycle badge, change type --%>
      <div class="flex items-start justify-between gap-2 mb-3">
        <div class="flex items-center gap-2">
          <%!-- Mobile: cycle number badge --%>
          <%= if @mobile do %>
            <span class={[
              "inline-flex items-center justify-center",
              "w-8 h-8 bg-surface-elevated border border-border",
              "font-mono-data text-xs font-bold text-text-primary"
            ]}>
              <%= @transition.to_cycle %>
            </span>
          <% end %>
          <span class="text-xs font-bold text-text-muted uppercase tracking-wider">
            Cycle <%= @transition.to_cycle %>
          </span>
        </div>
        <span class={[
          "text-xs font-mono-data font-bold whitespace-nowrap px-2 py-0.5",
          "border",
          transition_badge_styles(@transition.change_type)
        ]}>
          <%= format_change_type(@transition.change_type) %>
        </span>
      </div>

      <%!-- Claim text (truncated when collapsed, full when expanded) --%>
      <div class="mb-3">
        <p class={[
          "text-text-primary leading-relaxed",
          "text-sm",
          !@expanded && "line-clamp-2"
        ]}>
          <%= @transition.new_claim %>
        </p>
        <%!-- Truncation indicator when collapsed and text is long --%>
        <%= if !@expanded && String.length(@transition.new_claim) > 120 do %>
          <span class="text-xs text-text-muted">
            ... tap to expand
          </span>
        <% end %>
      </div>

      <%!-- Support level and delta - compact row --%>
      <div class="flex flex-wrap items-center gap-x-4 gap-y-1 mb-3 text-sm">
        <div class="flex items-baseline gap-1">
          <span class="text-xs text-text-muted uppercase tracking-wider">Support</span>
          <span class="font-mono-data text-text-primary">
            <%= format_support_level(@blackboard.id, @transition.to_cycle) %>
          </span>
        </div>
        <div class="flex items-baseline gap-1">
          <span class="text-xs text-text-muted uppercase tracking-wider">Delta</span>
          <span class={[
            "font-mono-data",
            support_delta_color(@blackboard.id, @transition.from_cycle, @transition.to_cycle)
          ]}>
            <%= format_support_delta(@blackboard.id, @transition.from_cycle, @transition.to_cycle) %>
          </span>
        </div>
      </div>

      <%!-- Trigger agent --%>
      <div class="flex items-center gap-2 text-xs text-text-muted mb-3">
        <span class="font-bold">Triggered by:</span>
        <span class="capitalize"><%= format_agent_role(@transition.trigger_agent) %></span>
      </div>

      <%!-- Brief quote from contribution (desktop only) --%>
      <%= if @show_contribution_excerpt && @transition.trigger_contribution && @transition.trigger_contribution.output_text do %>
        <div class="mb-3 p-2 bg-surface-elevated border border-border-subtle">
          <div class="text-xs text-text-muted mb-1">Contribution excerpt:</div>
          <div class="text-xs text-text-secondary leading-snug line-clamp-2">
            "<%= truncate_contribution(@transition.trigger_contribution.output_text, 120) %>"
          </div>
        </div>
      <% end %>

      <%!-- Expanded diff view --%>
      <%= if @expanded do %>
        <div
          id={"timeline-diff-#{@transition.id}"}
          class="mt-4 pt-4 border-t border-border"
        >
          <%!-- Mobile: show contribution excerpt in expanded view --%>
          <%= if @mobile && @transition.trigger_contribution && @transition.trigger_contribution.output_text do %>
            <div class="mb-4 p-2 bg-surface-elevated border border-border-subtle">
              <div class="text-xs text-text-muted mb-1">Contribution excerpt:</div>
              <div class="text-xs text-text-secondary leading-snug">
                "<%= truncate_contribution(@transition.trigger_contribution.output_text, 200) %>"
              </div>
            </div>
          <% end %>

          <div class="mb-3">
            <h3 class="text-xs font-bold uppercase tracking-wider text-text-muted mb-2">
              Previous Claim (Cycle <%= @transition.from_cycle %>)
            </h3>
            <p class="text-text-secondary text-sm leading-relaxed italic">
              <%= @transition.previous_claim %>
            </p>
          </div>

          <UnshackledWeb.Components.ClaimDiff.claim_diff
            previous_claim={@transition.previous_claim}
            new_claim={@transition.new_claim}
            diff_data={%{
              additions: @transition.diff_additions || %{},
              removals: @transition.diff_removals || %{},
              modifications: %{}
            }}
            mode={:inline}
          />
        </div>
      <% end %>

      <%!-- Expand/Collapse indicator --%>
      <div class="flex items-center justify-center mt-2 pt-2 border-t border-border-subtle">
        <span class={[
          "text-xs text-text-muted",
          "flex items-center gap-1"
        ]}>
          <%= if @expanded, do: "Show less", else: "Show more" %>
          <span class={[
            "transition-transform duration-200 inline-block",
            @expanded && "rotate-180"
          ]}>
            ▼
          </span>
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Checks if all timeline nodes are expanded.

  ## Examples

      iex> all_expanded?(%{1 => true, 2 => true}, [%{id: 1}, %{id: 2}])
      true

      iex> all_expanded?(%{1 => true}, [%{id: 1}, %{id: 2}])
      false
  """
  def all_expanded?(expanded_nodes, transitions) do
    transition_count = length(transitions)
    expanded_count = map_size(expanded_nodes)
    transition_count > 0 and expanded_count == transition_count
  end
end
