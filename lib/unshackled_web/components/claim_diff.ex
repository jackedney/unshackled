defmodule UnshackledWeb.Components.ClaimDiff do
  @moduledoc """
  Component for displaying visual diffs between claim versions.

  Highlights semantic changes with color-coded markup:
  - Green: added concepts
  - Red with strikethrough: removed concepts
  - Yellow: refined/modified concepts

  Supports both inline and side-by-side view modes.
  """

  use Phoenix.Component

  alias Unshackled.Evolution.ClaimDiff

  @doc """
  Renders a claim diff view.

  ## Attributes

  * `previous_claim` - The original claim text (required)
  * `new_claim` - The modified claim text (required)
  * `diff_data` - Structured diff data (optional, will be generated if not provided)
  * `mode` - Display mode: :inline (default) or :side_by_side
  * `class` - Additional CSS classes

  ## Examples

      <.claim_diff
        previous_claim="AI is good"
        new_claim="AI technology is beneficial for companies"
        mode={:inline}
      />

      <.claim_diff
        previous_claim="AI is good"
        new_claim="AI technology is beneficial for companies"
        diff_data={@diff}
        mode={:side_by_side}
      />
  """
  attr(:previous_claim, :string, required: true, doc: "the original claim text")
  attr(:new_claim, :string, required: true, doc: "the modified claim text")

  attr(:diff_data, :map,
    default: nil,
    doc: "structured diff data with additions, removals, modifications"
  )

  attr(:mode, :atom,
    default: :inline,
    values: [:inline, :side_by_side],
    doc: "display mode (:inline | :side_by_side)"
  )

  attr(:class, :string, default: nil, doc: "additional CSS classes")

  def claim_diff(assigns) do
    {previous_claim, new_claim, diff_data, _mode, _class} = {
      assigns.previous_claim,
      assigns.new_claim,
      assigns.diff_data,
      assigns.mode,
      assigns.class
    }

    {:ok, html_result} =
      ClaimDiff.highlight_changes(previous_claim, new_claim, diff_data)

    assigns =
      assigns
      |> assign(:previous_claim_html, html_result.previous_claim_html)
      |> assign(:new_claim_html, html_result.new_claim_html)

    ~H"""
    <div class={["claim-diff", @class]}>
      <%= case @mode do %>
        <% :inline -> %>
          <div class="flex flex-col gap-4">
            <div class="claim-diff-section">
              <h3 class="text-xs font-bold uppercase tracking-wider text-text-muted mb-2">
                Previous
              </h3>
              <div class="p-3 bg-surface border-2 border-border text-text-secondary leading-relaxed">
                <.diff_content html={@previous_claim_html} />
              </div>
            </div>

            <div class="claim-diff-section">
              <h3 class="text-xs font-bold uppercase tracking-wider text-text-muted mb-2">
                Current
              </h3>
              <div class="p-3 bg-surface-elevated border-2 border-border text-text-primary leading-relaxed">
                <.diff_content html={@new_claim_html} />
              </div>
            </div>
          </div>

        <% :side_by_side -> %>
          <div class="grid grid-cols-2 gap-4">
            <div class="claim-diff-section">
              <h3 class="text-xs font-bold uppercase tracking-wider text-text-muted mb-2">
                Previous
              </h3>
              <div class="p-3 bg-surface border-2 border-border text-text-secondary leading-relaxed">
                <.diff_content html={@previous_claim_html} />
              </div>
            </div>

            <div class="claim-diff-section">
              <h3 class="text-xs font-bold uppercase tracking-wider text-text-muted mb-2">
                Current
              </h3>
              <div class="p-3 bg-surface-elevated border-2 border-border text-text-primary leading-relaxed">
                <.diff_content html={@new_claim_html} />
              </div>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders diff HTML with safe handling of raw markup.
  """
  attr(:html, :string, required: true, doc: "HTML string with diff markup")

  def diff_content(assigns) do
    ~H"""
    <%= Phoenix.HTML.raw(@html) %>
    """
  end
end
