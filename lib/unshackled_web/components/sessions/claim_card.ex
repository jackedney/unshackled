defmodule UnshackledWeb.Components.Sessions.ClaimCard do
  @moduledoc """
  Component for displaying current claim with contextualized summary sections.

  Renders the current claim prominently along with expandable summary sections:
  - Context Summary
  - Evolution Narrative
  - Addressed Objections
  - Remaining Gaps
  """

  use Phoenix.Component

  import UnshackledWeb.CoreComponents, only: [card: 1]

  @doc """
  Renders the contextualized claim card with current claim and summary sections.

  ## Attributes

  * `current_claim` - The current claim text (required)
  * `claim_summary` - Map containing summary data (optional)
  * `expanded_summary_sections` - MapSet of expanded section IDs (optional, defaults to empty)

  ## Examples

      <.contextualized_claim_card 
        current_claim={@blackboard.current_claim}
        claim_summary={@claim_summary}
        expanded_summary_sections={@expanded_summary_sections}
      />
  """
  attr(:current_claim, :string, required: true, doc: "the current claim text")
  attr(:claim_summary, :map, default: nil, doc: "map containing summary data")

  attr(:expanded_summary_sections, :map,
    default: MapSet.new(),
    doc: "set of expanded section IDs"
  )

  def contextualized_claim_card(assigns) do
    ~H"""
    <.card class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold text-text-primary uppercase tracking-wider">
          Current Claim
        </h2>
        <%= if @claim_summary do %>
          <span class="text-xs text-text-muted">
            Cycle <%= @claim_summary.cycle_number %>
          </span>
        <% end %>
      </div>

      <%!-- Current claim (prominent) --%>
      <p class="text-text-secondary text-lg leading-relaxed font-medium">
        <%= @current_claim || "No claim" %>
      </p>

      <%!-- Summary sections (always rendered) --%>
      <div class="space-y-2">
        <.summary_collapsible_section
          title="Context Summary"
          section_id="context_summary"
          expanded={MapSet.member?(@expanded_summary_sections, "context_summary")}
        >
          <p class="text-text-primary leading-relaxed">
            <%= @claim_summary && @claim_summary.full_context_summary || "Awaiting first cycle..." %>
          </p>
        </.summary_collapsible_section>

        <.summary_collapsible_section
          title="Evolution Narrative"
          section_id="evolution_narrative"
          expanded={MapSet.member?(@expanded_summary_sections, "evolution_narrative")}
        >
          <p class="text-text-secondary text-sm leading-relaxed">
            <%= @claim_summary && @claim_summary.evolution_narrative || "Awaiting first cycle..." %>
          </p>
        </.summary_collapsible_section>

        <.summary_collapsible_section
          title="Addressed Objections"
          section_id="addressed_objections"
          expanded={MapSet.member?(@expanded_summary_sections, "addressed_objections")}
        >
          <%= if @claim_summary && @claim_summary.addressed_objections && @claim_summary.addressed_objections != %{} do %>
            <div class="text-text-secondary text-sm leading-relaxed">
              <%= Jason.encode!(@claim_summary.addressed_objections, pretty: true) %>
            </div>
          <% else %>
            <p class="text-text-secondary text-sm leading-relaxed">
              Awaiting first cycle...
            </p>
          <% end %>
        </.summary_collapsible_section>

        <.summary_collapsible_section
          title="Remaining Gaps"
          section_id="remaining_gaps"
          expanded={MapSet.member?(@expanded_summary_sections, "remaining_gaps")}
        >
          <%= if @claim_summary && @claim_summary.remaining_gaps && @claim_summary.remaining_gaps != %{} do %>
            <div class="text-text-secondary text-sm leading-relaxed">
              <%= Jason.encode!(@claim_summary.remaining_gaps, pretty: true) %>
            </div>
          <% else %>
            <p class="text-text-secondary text-sm leading-relaxed">
              Awaiting first cycle...
            </p>
          <% end %>
        </.summary_collapsible_section>
      </div>
    </.card>
    """
  end

  @doc """
  Renders a collapsible section for the claim card summary.

  ## Attributes

  * `title` - Section title (required)
  * `section_id` - Unique identifier for the section (required)
  * `expanded` - Whether the section is expanded (required)
  * `inner_block` - Content to display when expanded (required)
  """
  attr(:title, :string, required: true, doc: "section title")
  attr(:section_id, :string, required: true, doc: "unique section identifier")
  attr(:expanded, :boolean, required: true, doc: "whether the section is expanded")
  slot(:inner_block, required: true, doc: "content to display when expanded")

  def summary_collapsible_section(assigns) do
    ~H"""
    <div class="border-2 border-border bg-surface">
      <button
        type="button"
        phx-click="toggle_summary_section"
        phx-value-section={@section_id}
        class={[
          "w-full flex items-center justify-between p-4 text-left",
          "hover:bg-surface-elevated transition-colors"
        ]}
        aria-expanded={@expanded}
      >
        <span class="text-sm font-bold uppercase tracking-wider text-text-primary">
          <%= @title %>
        </span>
        <span class="text-text-muted transition-transform duration-200" style={"transform: rotate(#{@expanded && 180 || 0}deg)"}>
          ▼
        </span>
      </button>
      <div
        class="px-4 pb-4"
        style={if @expanded, do: "", else: "display: none;"}
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end
