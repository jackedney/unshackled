defmodule UnshackledWeb.Components.Sessions.ClaimsLists do
  @moduledoc """
  Components for displaying cemetery and graduated claims lists.

  Renders lists of claims that have died (in the cemetery) or graduated,
  with appropriate styling and empty state handling.
  """

  use Phoenix.Component

  import UnshackledWeb.SessionsLive.Show.Formatters,
    only: [
      format_support: 1
    ]

  @doc """
  Renders a list of claims that have died (cemetery).

  Each entry shows the cycle the claim was killed, final support level,
  the claim text, and the cause of death.

  ## Attributes

  * `entries` - List of cemetery entries with cycle_killed, final_support, claim, and cause_of_death (required)

  ## Examples

      <.cemetery_list entries={@cemetery_entries} />
  """
  attr(:entries, :list, required: true, doc: "list of cemetery entries")

  def cemetery_list(assigns) do
    ~H"""
    <div class="space-y-3">
      <%= if @entries == [] do %>
        <p class="text-text-muted text-sm">No claims have died</p>
      <% else %>
        <%= for entry <- @entries do %>
          <div class="border border-border-strong p-3 bg-background">
            <div class="flex items-start justify-between gap-4 mb-2">
              <span class="text-xs font-bold text-status-dead uppercase tracking-wider">
                Cycle <%= entry.cycle_killed %>
              </span>
              <span class="text-xs font-mono-data text-text-muted">
                Support: <%= format_support(entry.final_support) %>
              </span>
            </div>
            <p class="text-text-secondary text-sm leading-relaxed mb-2">
              <%= entry.claim %>
            </p>
            <p class="text-xs text-text-muted italic">
              Cause: <%= entry.cause_of_death %>
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a list of claims that have graduated.

  Each entry shows the cycle the claim graduated, final support level,
  and the claim text.

  ## Attributes

  * `claims` - List of graduated claims with cycle_graduated, final_support, and claim (required)

  ## Examples

      <.graduated_list claims={@graduated_claims} />
  """
  attr(:claims, :list, required: true, doc: "list of graduated claims")

  def graduated_list(assigns) do
    ~H"""
    <div class="space-y-3">
      <%= if @claims == [] do %>
        <p class="text-text-muted text-sm">No claims have graduated</p>
      <% else %>
        <%= for claim <- @claims do %>
          <div class="border border-status-graduated/30 p-3 bg-background">
            <div class="flex items-start justify-between gap-4 mb-2">
              <span class="text-xs font-bold text-status-graduated uppercase tracking-wider">
                Cycle <%= claim.cycle_graduated %>
              </span>
              <span class="text-xs font-mono-data text-text-muted">
                Support: <%= format_support(claim.final_support) %>
              </span>
            </div>
            <p class="text-text-secondary text-sm leading-relaxed">
              <%= claim.claim %>
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
