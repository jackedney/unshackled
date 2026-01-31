defmodule UnshackledWeb.Components.Sessions.CostCard do
  @moduledoc """
  Component for displaying session cost information.

  Renders cost breakdown by cycle and agent with visual indicators and
  progress bars showing cost distribution.
  """

  use Phoenix.Component

  import UnshackledWeb.CoreComponents, only: [card: 1]

  import UnshackledWeb.SessionsLive.Show.Formatters,
    only: [
      format_cost: 1,
      format_cost_limit: 1,
      calculate_limit_percentage: 2,
      limit_color: 2,
      format_agent_role: 1,
      agent_role_color: 1,
      calculate_agent_cost_percentage: 2
    ]

  @doc """
  Renders the main cost card with total cost and limit usage.

  ## Attributes

  * `total_cost` - Total session cost (required)
  * `cost_limit` - Optional cost limit (optional)

  ## Examples

      <.cost_card
        total_cost={@total_cost}
        cost_limit={@blackboard.cost_limit_usd}
      />
  """
  attr(:total_cost, :float, required: true, doc: "total session cost")
  attr(:cost_limit, :any, default: nil, doc: "optional cost limit")

  def cost_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-bold text-text-primary uppercase tracking-wider">
          Session Cost
        </h2>
      </div>

      <div class="flex items-baseline gap-2">
        <span class="text-4xl font-mono-data font-bold text-text-primary">
          <%= format_cost(@total_cost) %>
        </span>
        <%= if @cost_limit do %>
          <span class="text-lg text-text-muted">
            / <%= format_cost_limit(@cost_limit) %>
          </span>
        <% end %>
      </div>

      <%= if @cost_limit do %>
        <div class="mt-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-bold uppercase tracking-wider text-text-muted">
              Limit Used
            </span>
            <span class="text-xs font-mono-data text-text-primary">
              <%= calculate_limit_percentage(@total_cost, @cost_limit) %>
            </span>
          </div>
          <div class="w-full bg-surface-elevated rounded-full h-2">
            <div
              class={[
                "h-2 rounded-full transition-all duration-300",
                limit_color(@total_cost, @cost_limit)
              ]}
              style={"width: #{calculate_limit_percentage(@total_cost, @cost_limit)}"}
            >
            </div>
          </div>
        </div>
      <% end %>
    </.card>
    """
  end

  @doc """
  Renders a list of costs grouped by cycle.

  ## Attributes

  * `costs` - List of cycle cost entries (required)

  ## Examples

      <.cost_by_cycle_list costs={@cost_by_cycle} />
  """
  attr(:costs, :list, required: true, doc: "list of cycle cost entries")

  def cost_by_cycle_list(assigns) do
    ~H"""
    <div class="space-y-2">
     <%= if @costs == [] do %>
       <p class="text-text-muted text-sm italic">No cost data yet</p>
     <% else %>
       <%= for cost <- @costs do %>
         <div class="flex items-center justify-between py-2 px-3 bg-surface-elevated border border-border">
           <div class="flex items-center gap-3">
             <span class="text-xs font-bold text-text-muted uppercase tracking-wider">
               Cycle <%= cost.cycle_number %>
             </span>
           </div>
           <div class="flex items-center gap-4">
             <span class="font-mono-data text-text-primary">
               <%= format_cost(cost.total_cost) %>
             </span>
             <span class="text-xs text-text-muted">
               (<%= cost.total_tokens %> tokens)
             </span>
           </div>
         </div>
       <% end %>
     <% end %>
    </div>
    """
  end

  @doc """
  Renders a list of costs grouped by agent with percentage bars.

  ## Attributes

  * `costs` - List of agent cost entries (required)

  ## Examples

      <.cost_by_agent_list costs={@cost_by_agent} />
  """
  attr(:costs, :list, required: true, doc: "list of agent cost entries")

  def cost_by_agent_list(assigns) do
    ~H"""
    <div class="space-y-3">
     <%= if @costs == [] do %>
       <p class="text-text-muted text-sm italic">No cost data yet</p>
     <% else %>
       <%= for cost <- @costs do %>
         <div class="space-y-2">
           <div class="flex items-center justify-between py-2 px-3 bg-surface-elevated border border-border">
             <div class="flex items-center gap-3">
               <div class={[
                 "w-3 h-3 flex-shrink-0",
                 agent_role_color(cost.agent_role)
               ]}>
               </div>
               <span class="text-sm font-bold text-text-primary capitalize">
                 <%= format_agent_role(cost.agent_role) %>
               </span>
             </div>
             <div class="flex items-center gap-4">
               <span class="font-mono-data text-text-primary">
                 <%= format_cost(cost.total_cost) %>
               </span>
               <span class="text-xs text-text-muted">
                 (<%= cost.call_count %> calls)
               </span>
             </div>
           </div>
           <div class="pl-6 pr-3">
             <div class="w-full bg-surface-elevated rounded h-2">
               <div
                 class={[
                   "h-2 rounded",
                   agent_role_color(cost.agent_role)
                 ]}
                 style={"width: #{calculate_agent_cost_percentage(cost.total_cost, @costs)}"}
               >
               </div>
             </div>
           </div>
         </div>
       <% end %>
     <% end %>
    </div>
    """
  end
end
