defmodule UnshackledWeb.DashboardLive do
  @moduledoc """
  Dashboard LiveView - landing page showing current session status or start prompt.
  """
  use UnshackledWeb, :live_view_minimal

  import Ecto.Query

  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Repo
  alias Unshackled.Session
  alias UnshackledWeb.PubSub, as: WebPubSub

  # Refresh interval for polling (as fallback, in milliseconds)
  @refresh_interval 5_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket = assign_current_path(socket)
    socket = assign_session_data(socket)

    # Subscribe to PubSub updates when connected
    if connected?(socket) do
      WebPubSub.subscribe_sessions()

      # Subscribe to the active session's topic if there is one
      if socket.assigns[:session_id] do
        WebPubSub.subscribe_session(socket.assigns.session_id)
      end

      # Also subscribe to the blackboard topic for more granular updates
      if socket.assigns[:blackboard_id] do
        WebPubSub.subscribe_blackboard(socket.assigns.blackboard_id)
      end

      # Schedule periodic refresh as a fallback
      Process.send_after(self(), :refresh_data, @refresh_interval)
    end

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Dashboard
        <:subtitle>Session monitoring and control</:subtitle>
      </.header>

      <%= if @loading do %>
        <%!-- Refined skeleton loading state --%>
        <div class="hero-card p-8">
          <div class="flex items-center gap-3 mb-6">
            <div class="skeleton-shimmer h-5 w-28"></div>
            <div class="skeleton-shimmer h-6 w-20"></div>
          </div>
          <div class="skeleton-shimmer h-16 w-full mb-8"></div>
          <div class="divider mb-6"></div>
          <div class="grid grid-cols-3 gap-8">
            <div class="skeleton-shimmer h-28"></div>
            <div class="skeleton-shimmer h-28"></div>
            <div class="skeleton-shimmer h-28"></div>
          </div>
        </div>
      <% end %>

      <%= if @active_session and not @loading do %>
        <.active_session_panel
          session_id={@session_id}
          blackboard_id={@blackboard_id}
          claim={@current_claim}
          support_strength={@support_strength}
          support_history={@support_history}
          cycle_count={@cycle_count}
          cycle_history={@cycle_history}
          status={@session_status}
        />
      <% else %>
        <%= if not @loading do %>
          <.no_session_panel />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr(:session_id, :string, required: true)
  attr(:blackboard_id, :integer, required: true)
  attr(:claim, :string, required: true)
  attr(:support_strength, :float, required: true)
  attr(:support_history, :list, required: true)
  attr(:cycle_count, :integer, required: true)
  attr(:cycle_history, :list, required: true)
  attr(:status, :atom, required: true)

  defp active_session_panel(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Hero Card: Current Claim --%>
      <div class="hero-card p-8 animate-fade-in">
        <div class="flex items-start justify-between gap-6 mb-6">
          <div class="flex-1">
            <div class="flex items-center gap-3 mb-4">
              <span class="font-display text-xs font-semibold uppercase tracking-wider text-text-muted">
                Current Claim
              </span>
              <.status_badge status={@status} />
            </div>
            <p class="text-xl font-body font-medium text-text-primary leading-relaxed">
              <%= truncate_claim(@claim) %>
            </p>
          </div>
        </div>

        <%!-- Divider --%>
        <div class="divider my-6"></div>

        <%!-- Big Metrics Row with refined layout --%>
        <div class="grid grid-cols-3 gap-8">
          <%!-- Support Metric --%>
          <div class="text-center animate-fade-in stagger-1">
            <span class="block font-display text-[0.6875rem] font-semibold uppercase tracking-wider text-text-muted mb-3">
              Support
            </span>
            <span class={[
              "metric-large block",
              support_color_class(@support_strength)
            ]}>
              <%= format_support(@support_strength) %>
            </span>
            <span :if={support_trend(@support_history)} class="block mt-2 text-sm text-text-secondary font-body">
              <%= trend_text(support_trend(@support_history), @support_history) %>
            </span>
          </div>

          <%!-- Cycle Metric with vertical dividers --%>
          <div class="text-center relative animate-fade-in stagger-2">
            <div class="absolute left-0 top-4 bottom-4 w-px bg-gradient-to-b from-transparent via-border to-transparent"></div>
            <div class="absolute right-0 top-4 bottom-4 w-px bg-gradient-to-b from-transparent via-border to-transparent"></div>
            <span class="block font-display text-[0.6875rem] font-semibold uppercase tracking-wider text-text-muted mb-3">
              Cycle
            </span>
            <span class="metric-large text-accent block">
              <%= @cycle_count %>
            </span>
            <span class="block mt-2 text-sm text-text-secondary font-body">
              iterations
            </span>
          </div>

          <%!-- Session ID --%>
          <div class="text-center animate-fade-in stagger-3">
            <span class="block font-display text-[0.6875rem] font-semibold uppercase tracking-wider text-text-muted mb-3">
              Session
            </span>
            <span class="metric-large text-text-primary block">
              #<%= @blackboard_id %>
            </span>
            <span class="block mt-2 text-sm text-text-secondary font-body">
              active now
            </span>
          </div>
        </div>
      </div>

      <%!-- Action Buttons with refined spacing --%>
      <div class="flex items-center justify-between animate-fade-in stagger-2">
        <a href={"/sessions/#{@blackboard_id}"}>
          <.button variant={:primary}>
            View Full Details
          </.button>
        </a>
        <a href="/sessions">
          <.button variant={:secondary}>
            All Sessions
          </.button>
        </a>
      </div>

      <%!-- Support History Widget --%>
      <div class="widget-panel animate-fade-in stagger-3">
        <div class="widget-header flex items-center justify-between">
          <span>Support History</span>
          <span class="tag tag-accent">
            <%= length(@support_history) %> points
          </span>
        </div>
        <div class="p-6">
          <%= if @support_history != [] do %>
            <div class="h-24">
              <.sparkline
                data={Enum.map(@support_history, fn x -> x * 100 end)}
                width={600}
                height={96}
                color={sparkline_color(support_color(@support_strength))}
              />
            </div>
          <% else %>
            <p class="text-center text-text-muted py-8 font-body">No history yet</p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp no_session_panel(assigns) do
    ~H"""
    <div class="space-y-6 animate-fade-in">
      <%!-- Empty State Hero with refined styling --%>
      <div class="hero-card p-12 text-center">
        <%!-- Decorative accent line --%>
        <div class="w-16 h-1 bg-accent mx-auto mb-8"></div>

        <h1 class="font-display text-3xl font-bold tracking-tight text-text-primary mb-4">
          No Active Session
        </h1>
        <p class="font-body text-base text-text-secondary mb-10 max-w-md mx-auto leading-relaxed">
          Start reasoning about a claim. The system will iteratively refine and stress-test your ideas through multi-agent collaboration.
        </p>
        <a href="/sessions/new">
          <.button variant={:primary} class="text-sm px-8 py-3">
            <span class="flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-4 h-4">
                <path d="M8 2a.75.75 0 0 1 .75.75v4.5h4.5a.75.75 0 0 1 0 1.5h-4.5v4.5a.75.75 0 0 1-1.5 0v-4.5h-4.5a.75.75 0 0 1 0-1.5h4.5v-4.5A.75.75 0 0 1 8 2Z" />
              </svg>
              Start New Session
            </span>
          </.button>
        </a>
      </div>

      <%!-- Quick Actions --%>
      <div class="flex justify-center">
        <a href="/sessions">
          <.button variant={:secondary}>
            View Sessions
          </.button>
        </a>
      </div>
    </div>
    """
  end

  defp assign_session_data(socket) do
    socket
    |> assign(:loading, true)
    |> then(fn socket ->
      case get_active_session_with_blackboard() do
        {:ok, {session_id, info, blackboard}} ->
          support_history = get_support_history(blackboard.id)
          cycle_history = get_cycle_history(blackboard.id)

          socket
          |> assign(:active_session, true)
          |> assign(:session_id, session_id)
          |> assign(:blackboard_id, blackboard.id)
          |> assign(:session_status, info.status)
          |> assign(:current_claim, blackboard.current_claim)
          |> assign(:support_strength, blackboard.support_strength)
          |> assign(:cycle_count, blackboard.cycle_count)
          |> assign(:support_history, support_history)
          |> assign(:cycle_history, cycle_history)
          |> assign(:loading, false)

        {:ok, nil} ->
          socket
          |> assign(:active_session, false)
          |> assign(:session_id, nil)
          |> assign(:blackboard_id, nil)
          |> assign(:session_status, nil)
          |> assign(:current_claim, nil)
          |> assign(:support_strength, nil)
          |> assign(:cycle_count, nil)
          |> assign(:support_history, [])
          |> assign(:cycle_history, [])
          |> assign(:loading, false)
      end
    end)
  end

  defp get_active_session_with_blackboard do
    case Session.get_active_session() do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {session_id, info}} ->
        blackboard = get_blackboard_data(info.blackboard_id)
        {:ok, {session_id, info, blackboard}}
    end
  rescue
    # Handle case where Session GenServer is not running
    _error ->
      {:ok, nil}
  end

  defp get_blackboard_data(nil),
    do: %{current_claim: nil, support_strength: 0.5, cycle_count: 0, id: nil}

  defp get_blackboard_data(blackboard_id) do
    case Repo.get(BlackboardRecord, blackboard_id) do
      nil ->
        %{current_claim: nil, support_strength: 0.5, cycle_count: 0, id: nil}

      record ->
        %{
          current_claim: record.current_claim,
          support_strength: record.support_strength,
          cycle_count: record.cycle_count,
          id: record.id
        }
    end
  end

  defp truncate_claim(nil), do: "No claim"
  defp truncate_claim(claim) when byte_size(claim) > 200, do: String.slice(claim, 0, 200) <> "..."
  defp truncate_claim(claim), do: claim

  defp format_support(nil), do: "—"
  defp format_support(support), do: "#{Float.round(support * 100, 1)}%"

  defp support_color(nil), do: nil
  defp support_color(support) when support >= 0.7, do: :success
  defp support_color(support) when support >= 0.4, do: :warning
  defp support_color(_support), do: :danger

  defp support_color_class(nil), do: "text-text-muted"
  defp support_color_class(support) when support >= 0.7, do: "text-status-active"
  defp support_color_class(support) when support >= 0.4, do: "text-status-paused"
  defp support_color_class(_support), do: "text-status-dead"

  defp trend_text(:up, history) do
    if length(history) >= 2 do
      first = hd(history)
      last = List.last(history)
      diff = Float.round((last - first) * 100, 1)
      "+#{diff}% trending up"
    else
      "trending up"
    end
  end

  defp trend_text(:down, history) do
    if length(history) >= 2 do
      first = hd(history)
      last = List.last(history)
      diff = Float.round((first - last) * 100, 1)
      "-#{diff}% trending down"
    else
      "trending down"
    end
  end

  defp trend_text(:flat, _history), do: "stable"
  defp trend_text(nil, _history), do: nil

  defp sparkline_color(nil), do: "#666666"
  defp sparkline_color(:success), do: "#00ff88"
  defp sparkline_color(:warning), do: "#ffcc00"
  defp sparkline_color(:danger), do: "#ff3333"

  defp get_support_history(nil), do: []

  defp get_support_history(blackboard_id) do
    TrajectoryPoint
    |> where([tp], tp.blackboard_id == ^blackboard_id)
    |> order_by([tp], asc: tp.cycle_number)
    |> select([tp], tp.support_strength)
    |> limit(10)
    |> Repo.all()
  end

  defp get_cycle_history(nil), do: []

  defp get_cycle_history(blackboard_id) do
    TrajectoryPoint
    |> where([tp], tp.blackboard_id == ^blackboard_id)
    |> order_by([tp], asc: tp.cycle_number)
    |> select([tp], tp.cycle_number)
    |> limit(10)
    |> Repo.all()
  end

  defp support_trend([]), do: nil
  defp support_trend([_single]), do: nil

  defp support_trend(history) do
    first = hd(history)
    last = List.last(history)

    cond do
      last > first + 0.05 -> :up
      last < first - 0.05 -> :down
      true -> :flat
    end
  end

  defp assign_current_path(socket) do
    request_path = get_request_path(socket)
    assign(socket, :current_path, request_path || "/")
  end

  defp get_request_path(socket) do
    case socket.private[:connect_info] do
      %{request_path: path} when is_binary(path) -> path
      _ -> nil
    end
  end

  # ============================================================================
  # PubSub Event Handlers
  # ============================================================================

  @impl Phoenix.LiveView
  def handle_info(:refresh_data, socket) do
    # Periodic refresh as fallback - reschedule and refresh data
    Process.send_after(self(), :refresh_data, @refresh_interval)
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_started, session_id, blackboard_id}, socket) do
    # Subscribe to the new session
    WebPubSub.subscribe_session(session_id)
    WebPubSub.subscribe_blackboard(blackboard_id)
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_paused, _session_id}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_resumed, _session_id}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_stopped, _session_id}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_completed, _session_id}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:cycle_complete, _cycle_data}, socket) do
    # Cycle completed - refresh to show updated metrics
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:cycle_started, _cycle_data}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:blackboard_updated, _blackboard_state}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:claim_updated, _new_claim}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:support_updated, _new_support}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:summary_updated, _blackboard_id, _summary}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:cost_recorded, _session_id, _blackboard_id, _cost_data}, socket) do
    {:noreply, refresh_session_data(socket)}
  end

  # Catch-all for other PubSub messages
  @impl Phoenix.LiveView
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper to refresh session data without showing loading state
  defp refresh_session_data(socket) do
    old_session_id = socket.assigns[:session_id]
    old_blackboard_id = socket.assigns[:blackboard_id]

    socket = do_assign_session_data(socket)

    new_session_id = socket.assigns[:session_id]
    new_blackboard_id = socket.assigns[:blackboard_id]

    # Handle subscription changes if session changed
    socket =
      if old_session_id != new_session_id do
        if old_session_id, do: WebPubSub.unsubscribe_session(old_session_id)
        if new_session_id, do: WebPubSub.subscribe_session(new_session_id)
        socket
      else
        socket
      end

    # Handle blackboard subscription changes
    if old_blackboard_id != new_blackboard_id do
      if old_blackboard_id, do: WebPubSub.unsubscribe_blackboard(old_blackboard_id)
      if new_blackboard_id, do: WebPubSub.subscribe_blackboard(new_blackboard_id)
    end

    socket
  end

  # Core data assignment logic (without loading state management)
  defp do_assign_session_data(socket) do
    case get_active_session_with_blackboard() do
      {:ok, {session_id, info, blackboard}} ->
        support_history = get_support_history(blackboard.id)
        cycle_history = get_cycle_history(blackboard.id)

        socket
        |> assign(:active_session, true)
        |> assign(:session_id, session_id)
        |> assign(:blackboard_id, blackboard.id)
        |> assign(:session_status, info.status)
        |> assign(:current_claim, blackboard.current_claim)
        |> assign(:support_strength, blackboard.support_strength)
        |> assign(:cycle_count, blackboard.cycle_count)
        |> assign(:support_history, support_history)
        |> assign(:cycle_history, cycle_history)
        |> assign(:loading, false)

      {:ok, nil} ->
        socket
        |> assign(:active_session, false)
        |> assign(:session_id, nil)
        |> assign(:blackboard_id, nil)
        |> assign(:session_status, nil)
        |> assign(:current_claim, nil)
        |> assign(:support_strength, nil)
        |> assign(:cycle_count, nil)
        |> assign(:support_history, [])
        |> assign(:cycle_history, [])
        |> assign(:loading, false)
    end
  end
end
