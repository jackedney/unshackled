defmodule UnshackledWeb.SessionsLive.Show do
  @moduledoc """
  Session detail LiveView - displays live session state with real-time updates.
  """
  use UnshackledWeb, :live_view_minimal

  alias UnshackledWeb.Components.Sessions.SessionDetail

  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Costs
  alias Unshackled.Session
  alias UnshackledWeb.PubSub

  import UnshackledWeb.SessionsLive.Show.DataLoader,
    only: [
      load_blackboard: 1,
      load_support_timeline: 1,
      load_contributions_data: 1,
      load_trajectory_data: 1,
      load_cemetery_entries: 1,
      load_graduated_claims: 1,
      load_cycle_log: 3,
      load_claim_transitions: 1,
      load_claim_summary: 2,
      load_session_data_fast: 2
    ]

  import UnshackledWeb.SessionsLive.Show.State,
    only: [build_found_state: 4, build_not_found_state: 0, build_refresh_state: 4]

  import UnshackledWeb.SessionsLive.Show.Helpers,
    only: [
      find_session_id_for_blackboard: 1,
      determine_status: 2,
      expand_all_ids: 1,
      assign_current_path: 1,
      update_blackboard_field: 3
    ]

  require Jason

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    socket = assign_current_path(socket)

    case load_blackboard(id) do
      {:ok, blackboard} ->
        {:ok, mount_with_blackboard(socket, blackboard)}

      {:error, :not_found} ->
        {:ok, mount_not_found(socket)}
    end
  end

  defp mount_with_blackboard(socket, blackboard) do
    session_id = find_session_id_for_blackboard(blackboard.id)
    maybe_subscribe(socket, session_id, blackboard.id)

    # Load non-blocking data synchronously
    session_data = load_session_data_fast(blackboard.id, session_id)
    {cycle_log, has_more_cycles} = load_cycle_log(blackboard.id, 0, 10)
    claim_summary = load_claim_summary(blackboard.id, blackboard.cycle_count)
    claim_transitions = load_claim_transitions(blackboard.id)

    socket =
      assign(
        socket,
        build_found_state(blackboard, session_id, session_data,
          status: determine_status(blackboard, session_id),
          cycle_log: cycle_log,
          has_more_cycles: has_more_cycles,
          claim_summary: claim_summary,
          claim_transitions: claim_transitions
        )
      )

    # Load trajectory data asynchronously (t-SNE is computationally expensive)
    if connected?(socket) do
      send(self(), {:load_trajectory_data, blackboard.id})
    end

    socket
  end

  defp mount_not_found(socket) do
    assign(socket, build_not_found_state())
  end

  defp maybe_subscribe(socket, session_id, blackboard_id) do
    if connected?(socket) and session_id do
      PubSub.subscribe_session(session_id)
    end

    if connected?(socket) and blackboard_id do
      PubSub.subscribe_blackboard(blackboard_id)
    end
  end

  defp load_session_data(blackboard_id, session_id) do
    %{
      support_timeline: load_support_timeline(blackboard_id),
      contributions_data: load_contributions_data(blackboard_id),
      trajectory_data: load_trajectory_data(blackboard_id),
      cemetery_entries: load_cemetery_entries(blackboard_id),
      graduated_claims: load_graduated_claims(session_id)
    }
  end

  defp assign_session_data(socket, data) do
    assign(socket, %{
      support_timeline: data.support_timeline,
      contributions_data: data.contributions_data,
      cemetery_entries: data.cemetery_entries,
      graduated_claims: data.graduated_claims
    })
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= if @not_found do %>
     <.not_found_view />
    <% else %>
     <SessionDetail.session_detail
       blackboard={@blackboard}
       session_id={@session_id}
       status={@status}
       show_stop_confirm={@show_stop_confirm}
       show_delete_confirm={@show_delete_confirm}
       support_timeline={@support_timeline}
       contributions_data={@contributions_data}
       trajectory_data={@trajectory_data}
       trajectory_loading={@trajectory_loading}
       cemetery_entries={@cemetery_entries}
       graduated_claims={@graduated_claims}
       cycle_log={@cycle_log}
       has_more_cycles={@has_more_cycles}
       new_cycle_number={@new_cycle_number}
       claim_summary={@claim_summary}
       claim_transitions={@claim_transitions}
       expanded_timeline_nodes={@expanded_timeline_nodes}
       expanded_summary_sections={@expanded_summary_sections}
       total_cost={@total_cost}
       cost_by_cycle={@cost_by_cycle}
       cost_by_agent={@cost_by_agent}
     />
    <% end %>
    """
  end

  defp not_found_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Session Not Found
        <:subtitle>The requested session does not exist</:subtitle>
      </.header>

      <.card class="text-center py-12">
        <p class="text-text-secondary text-lg">Session not found</p>
        <p class="mt-2 text-text-muted text-sm">
          The session you're looking for doesn't exist or has been deleted.
        </p>
        <div class="mt-6">
          <a href="/sessions">
            <.button variant={:secondary}>Back to Sessions</.button>
          </a>
        </div>
      </.card>
    </div>
    """
  end

  # Session control event handlers

  @impl Phoenix.LiveView
  def handle_event("pause_session", _params, socket) do
    case Session.pause(socket.assigns.session_id) do
      :ok ->
        {:noreply, assign(socket, :status, :paused)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("resume_session", _params, socket) do
    case Session.resume(socket.assigns.session_id) do
      :ok ->
        {:noreply, assign(socket, :status, :running)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("show_stop_confirm", _params, socket) do
    {:noreply, assign(socket, :show_stop_confirm, true)}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_stop", _params, socket) do
    {:noreply, assign(socket, :show_stop_confirm, false)}
  end

  @impl Phoenix.LiveView
  def handle_event("confirm_stop", _params, socket) do
    case Session.stop(socket.assigns.session_id) do
      :ok ->
        socket =
          socket
          |> assign(:status, :stopped)
          |> assign(:show_stop_confirm, false)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:show_stop_confirm, false)
          |> put_flash(:error, "Failed to stop: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("show_delete_confirm", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  @impl Phoenix.LiveView
  def handle_event("confirm_delete", _params, socket) do
    blackboard = socket.assigns.blackboard

    # Stop the session if it exists and is running
    if socket.assigns.session_id do
      Session.stop(socket.assigns.session_id)
    end

    case BlackboardRecord.delete(blackboard) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Session ##{blackboard.id} deleted")
          |> push_navigate(to: "/sessions")

        {:noreply, socket}

      {:error, _changeset} ->
        socket =
          socket
          |> assign(:show_delete_confirm, false)
          |> put_flash(:error, "Failed to delete session")

        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_more_cycles", _params, socket) do
    blackboard_id = socket.assigns.blackboard.id
    current_offset = socket.assigns.cycle_log_offset

    {more_cycles, has_more} = load_cycle_log(blackboard_id, current_offset, 10)

    socket =
      socket
      |> assign(:cycle_log, socket.assigns.cycle_log ++ more_cycles)
      |> assign(:cycle_log_offset, current_offset + length(more_cycles))
      |> assign(:has_more_cycles, has_more)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_timeline_node", %{"node" => node_id}, socket) do
    node_id = String.to_integer(node_id)
    toggle_timeline_node_map(socket, node_id)
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_all_timeline_nodes", _params, socket) do
    transition_ids = Enum.map(socket.assigns.claim_transitions, & &1.id)
    current_expanded = socket.assigns.expanded_timeline_nodes
    all_expanded = length(current_expanded) == length(transition_ids)

    toggle_all_timeline_nodes(socket, not all_expanded)
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_summary_section", %{"section" => section_id}, socket) do
    toggle_summary_section_map(socket, section_id)
  end

  @impl Phoenix.LiveView
  def handle_info({:claim_changed, blackboard_id, _transition}, socket) do
    if socket.assigns.blackboard.id == blackboard_id do
      claim_transitions = load_claim_transitions(blackboard_id)
      session_data = load_session_data(blackboard_id, socket.assigns.session_id)

      socket =
        socket
        |> assign(:claim_transitions, claim_transitions)
        |> assign_session_data(session_data)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:summary_updated, blackboard_id, _summary}, socket) do
    if socket.assigns.blackboard.id == blackboard_id do
      current_cycle_count = socket.assigns.blackboard.cycle_count
      claim_summary = load_claim_summary(blackboard_id, current_cycle_count)

      socket =
        socket
        |> assign(:claim_summary, claim_summary)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Async data loading handlers

  @impl Phoenix.LiveView
  def handle_info({:load_trajectory_data, blackboard_id}, socket) do
    # Load trajectory data in a separate process to avoid blocking
    lv_pid = self()

    Task.start(fn ->
      trajectory_data = load_trajectory_data(blackboard_id)
      send(lv_pid, {:trajectory_data_loaded, trajectory_data})
    end)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:trajectory_data_loaded, trajectory_data}, socket) do
    socket =
      socket
      |> assign(:trajectory_data, trajectory_data)
      |> assign(:trajectory_loading, false)

    {:noreply, socket}
  end

  # PubSub event handlers

  @impl Phoenix.LiveView
  def handle_info({:cycle_complete, cycle_data}, socket) do
    new_cycle_number = Map.get(cycle_data, :cycle_number)
    # Trigger async trajectory reload for the 3D plot
    send(self(), {:load_trajectory_data, socket.assigns.blackboard.id})
    {:noreply, refresh_session_data(socket, new_cycle_number)}
  end

  @impl Phoenix.LiveView
  def handle_info({:blackboard_updated, blackboard_state}, socket) do
    # Update with the broadcasted state
    blackboard = socket.assigns.blackboard

    updated_blackboard = %{
      blackboard
      | current_claim: Map.get(blackboard_state, :current_claim, blackboard.current_claim),
        support_strength:
          Map.get(blackboard_state, :support_strength, blackboard.support_strength),
        active_objection:
          Map.get(blackboard_state, :active_objection, blackboard.active_objection),
        analogy_of_record:
          Map.get(blackboard_state, :analogy_of_record, blackboard.analogy_of_record),
        cycle_count: Map.get(blackboard_state, :cycle_count, blackboard.cycle_count)
    }

    {:noreply, assign(socket, :blackboard, updated_blackboard)}
  end

  @impl Phoenix.LiveView
  def handle_info({:claim_updated, new_claim}, socket) do
    update_blackboard_field(socket, :current_claim, new_claim)
  end

  @impl Phoenix.LiveView
  def handle_info({:support_updated, new_support}, socket) do
    update_blackboard_field(socket, :support_strength, new_support)
  end

  @impl Phoenix.LiveView
  def handle_info({event, _session_id}, socket)
      when event in [:session_paused, :session_resumed, :session_stopped, :session_completed] do
    status =
      case event do
        :session_paused -> :paused
        :session_resumed -> :running
        :session_stopped -> :stopped
        :session_completed -> :completed
      end

    {:noreply, assign(socket, :status, status)}
  end

  @impl Phoenix.LiveView
  def handle_info({:cost_recorded, _session_id, blackboard_id, cost_data}, socket) do
    if socket.assigns.blackboard.id == blackboard_id do
      total_cost = Map.get(cost_data, :total_cost, 0.0)
      cost_by_cycle = Costs.get_cost_by_cycle(blackboard_id)
      cost_by_agent = Costs.get_cost_by_agent(blackboard_id)

      {:noreply,
       assign(socket,
         total_cost: total_cost,
         cost_by_cycle: cost_by_cycle,
         cost_by_agent: cost_by_agent
       )}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:cycle_started, _cycle_data}, socket) do
    # Could add a "processing" indicator here
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:claim_died, _cemetery_entry}, socket) do
    # Reload to get updated cemetery
    case load_blackboard(socket.assigns.blackboard.id) do
      {:ok, blackboard} ->
        cemetery_entries = load_cemetery_entries(blackboard.id)

        socket =
          socket
          |> assign(:blackboard, blackboard)
          |> assign(:cemetery_entries, cemetery_entries)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:claim_graduated, _graduated_entry}, socket) do
    # Reload to get updated state
    case load_blackboard(socket.assigns.blackboard.id) do
      {:ok, blackboard} ->
        graduated_claims = load_graduated_claims(socket.assigns.session_id)

        socket =
          socket
          |> assign(:blackboard, blackboard)
          |> assign(:status, :graduated)
          |> assign(:graduated_claims, graduated_claims)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(_msg, socket) do
    # Ignore unhandled messages
    {:noreply, socket}
  end

  # Private functions

  defp refresh_session_data(socket, new_cycle_number) do
    case load_blackboard(socket.assigns.blackboard.id) do
      {:ok, blackboard} ->
        # Use fast loader - trajectory data is loaded asynchronously
        session_data = load_session_data_fast(blackboard.id, socket.assigns.session_id)
        {cycle_log, has_more_cycles} = load_cycle_log(blackboard.id, 0, 10)

        assign(
          socket,
          build_refresh_state(
            blackboard,
            socket.assigns.session_id,
            session_data,
            status: determine_status(blackboard, socket.assigns.session_id),
            cycle_log: cycle_log,
            has_more_cycles: has_more_cycles,
            new_cycle_number: new_cycle_number
          )
        )

      {:error, :not_found} ->
        assign(socket, :not_found, true)
    end
  end

  defp toggle_timeline_node_map(socket, node_id) do
    expanded_nodes = socket.assigns.expanded_timeline_nodes

    new_expanded_nodes =
      if Map.has_key?(expanded_nodes, node_id) do
        Map.delete(expanded_nodes, node_id)
      else
        Map.put(expanded_nodes, node_id, true)
      end

    {:noreply, assign(socket, :expanded_timeline_nodes, new_expanded_nodes)}
  end

  defp toggle_all_timeline_nodes(socket, should_expand) do
    transition_ids = Enum.map(socket.assigns.claim_transitions, & &1.id)

    new_expanded_nodes =
      if should_expand, do: expand_all_ids(transition_ids), else: %{}

    {:noreply, assign(socket, :expanded_timeline_nodes, new_expanded_nodes)}
  end

  defp toggle_summary_section_map(socket, section_id) do
    expanded_sections = socket.assigns.expanded_summary_sections

    new_expanded_sections =
      if MapSet.member?(expanded_sections, section_id) do
        MapSet.delete(expanded_sections, section_id)
      else
        MapSet.put(expanded_sections, section_id)
      end

    {:noreply, assign(socket, :expanded_summary_sections, new_expanded_sections)}
  end
end
