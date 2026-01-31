defmodule UnshackledWeb.SessionsLive.Index do
  @moduledoc """
  Sessions list LiveView - displays all sessions with status indicators.
  """
  use UnshackledWeb, :live_view_minimal

  import Ecto.Query

  alias Phoenix.LiveView.JS
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo
  alias Unshackled.Session
  alias UnshackledWeb.PubSub

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: PubSub.subscribe_sessions()

    socket = assign_current_path(socket)
    page_size = 10

    case list_sessions_with_status(page: 0, page_size: page_size) do
      {:ok, sessions, has_more} ->
        {:ok,
         assign(socket,
           sessions: sessions,
           error: nil,
           page: 0,
           page_size: page_size,
           loading: false,
           has_more: has_more,
           show_clear_confirm: false,
           show_delete_confirm: nil
         )}

      {:error, reason} ->
        {:ok,
         assign(socket,
           sessions: [],
           error: format_db_error(reason),
           page: 0,
           page_size: page_size,
           loading: false,
           has_more: false,
           show_clear_confirm: false,
           show_delete_confirm: nil
         )}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Sessions
        <:subtitle>All reasoning sessions</:subtitle>
        <:actions>
          <%= if @sessions != [] do %>
            <.button phx-click="show_clear_confirm" variant={:danger}>
              <span class="flex items-center gap-1.5">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3.5 h-3.5">
                  <path fill-rule="evenodd" d="M5 3.25V4H2.75a.75.75 0 0 0 0 1.5h.3l.815 8.15A1.5 1.5 0 0 0 5.357 15h5.285a1.5 1.5 0 0 0 1.493-1.35l.815-8.15h.3a.75.75 0 0 0 0-1.5H11v-.75A2.25 2.25 0 0 0 8.75 1h-1.5A2.25 2.25 0 0 0 5 3.25Zm2.25-.75a.75.75 0 0 0-.75.75V4h3v-.75a.75.75 0 0 0-.75-.75h-1.5ZM6.05 6a.75.75 0 0 1 .787.713l.275 5.5a.75.75 0 0 1-1.498.075l-.275-5.5A.75.75 0 0 1 6.05 6Zm3.9 0a.75.75 0 0 1 .712.787l-.275 5.5a.75.75 0 0 1-1.498-.075l.275-5.5a.75.75 0 0 1 .786-.711Z" clip-rule="evenodd" />
                </svg>
                Clear All
              </span>
            </.button>
          <% end %>
          <a href="/sessions/new">
            <.button variant={:primary}>
              <span class="flex items-center gap-1.5">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3.5 h-3.5">
                  <path d="M8 2a.75.75 0 0 1 .75.75v4.5h4.5a.75.75 0 0 1 0 1.5h-4.5v4.5a.75.75 0 0 1-1.5 0v-4.5h-4.5a.75.75 0 0 1 0-1.5h4.5v-4.5A.75.75 0 0 1 8 2Z" />
                </svg>
                New Session
              </span>
            </.button>
          </a>
        </:actions>
      </.header>

      <%!-- Clear All confirmation modal --%>
      <.modal
        id="clear-confirm-modal"
        show={@show_clear_confirm}
        on_close={JS.push("cancel_clear")}
        class="border-status-dead"
      >
        <:title>
          <span class="text-status-dead">Clear All Sessions</span>
        </:title>
        <p class="mb-4">
          Are you sure you want to delete <strong>all <%= length(@sessions) %> sessions</strong>?
        </p>
        <p class="text-status-dead font-bold">
          This action cannot be undone. All session data, contributions, and history will be permanently deleted.
        </p>
        <:actions>
          <.button phx-click="cancel_clear" variant={:secondary}>
            Cancel
          </.button>
          <.button phx-click="confirm_clear" variant={:danger}>
            Delete All Sessions
          </.button>
        </:actions>
      </.modal>

      <%!-- Delete single session confirmation modal --%>
      <.modal
        :if={@show_delete_confirm}
        id="delete-confirm-modal"
        show={@show_delete_confirm != nil}
        on_close={JS.push("cancel_delete")}
        class="border-status-dead"
      >
        <:title>
          <span class="text-status-dead">Delete Session</span>
        </:title>
        <p class="mb-4">
          Are you sure you want to delete <strong>Session #<%= @show_delete_confirm %></strong>?
        </p>
        <p class="text-status-dead font-bold">
          This action cannot be undone. All session data will be permanently deleted.
        </p>
        <:actions>
          <.button phx-click="cancel_delete" variant={:secondary}>
            Cancel
          </.button>
          <.button phx-click="confirm_delete" phx-value-id={@show_delete_confirm} variant={:danger}>
            Delete Session
          </.button>
        </:actions>
      </.modal>

      <%= if @error do %>
        <.error_card
          title="Failed to load sessions"
          message={@error}
          retry
        />
      <% else %>
        <%= if @sessions == [] and not @loading do %>
          <.empty_state />
        <% else %>
          <div id="sessions-container" phx-hook="InfiniteScrollHook" class="space-y-3 overflow-y-auto">
            <.sessions_list sessions={@sessions} />

            <%= if @loading do %>
              <div class="space-y-3">
                <.skeleton_card />
                <.skeleton_card />
                <.skeleton_card />
              </div>
            <% end %>

            <%= if not @has_more and not @loading and @sessions != [] do %>
              <div class="text-center py-6">
                <div class="inline-flex items-center gap-2 text-text-muted text-xs font-display uppercase tracking-wider">
                  <div class="w-8 h-px bg-border"></div>
                  <span>End of list</span>
                  <div class="w-8 h-px bg-border"></div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("retry", _params, socket) do
    page_size = socket.assigns.page_size

    case list_sessions_with_status(page: 0, page_size: page_size) do
      {:ok, sessions, has_more} ->
        {:noreply,
         assign(socket,
           sessions: sessions,
           error: nil,
           page: 0,
           has_more: has_more
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: format_db_error(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("view_session", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: "/sessions/#{id}")}
  end

  @impl Phoenix.LiveView
  def handle_event("load_more", _params, socket) do
    if socket.assigns.loading or not socket.assigns.has_more do
      {:noreply, socket}
    else
      socket = assign(socket, loading: true)
      next_page = socket.assigns.page + 1

      case list_sessions_with_status(page: next_page, page_size: socket.assigns.page_size) do
        {:ok, new_sessions, has_more} ->
          {:noreply,
           socket
           |> assign(
             sessions: socket.assigns.sessions ++ new_sessions,
             page: next_page,
             loading: false,
             has_more: has_more
           )}

        {:error, reason} ->
          {:noreply, assign(socket, loading: false, error: format_db_error(reason))}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("show_clear_confirm", _params, socket) do
    {:noreply, assign(socket, :show_clear_confirm, true)}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_clear", _params, socket) do
    {:noreply, assign(socket, :show_clear_confirm, false)}
  end

  @impl Phoenix.LiveView
  def handle_event("confirm_clear", _params, socket) do
    # Stop all running sessions first
    Session.list_sessions()
    |> Enum.each(fn {session_id, status} ->
      if status in [:running, :paused] do
        Session.stop(session_id)
      end
    end)

    # Delete all blackboard records (cascades to all related tables)
    {count, _} = BlackboardRecord.delete_all()

    socket =
      socket
      |> assign(:sessions, [])
      |> assign(:show_clear_confirm, false)
      |> assign(:has_more, false)
      |> assign(:page, 0)
      |> put_flash(:info, "Deleted #{count} sessions")

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("show_delete_confirm", %{"id" => id}, socket) do
    {:noreply, assign(socket, :show_delete_confirm, String.to_integer(id))}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    blackboard_id = String.to_integer(id)

    # Stop the session if it's running
    stop_session_for_blackboard(blackboard_id)

    # Delete the blackboard record
    case Repo.get(BlackboardRecord, blackboard_id) do
      nil ->
        socket =
          socket
          |> assign(:show_delete_confirm, nil)
          |> put_flash(:error, "Session not found")

        {:noreply, socket}

      blackboard ->
        case BlackboardRecord.delete(blackboard) do
          {:ok, _} ->
            # Remove from the list
            sessions = Enum.reject(socket.assigns.sessions, &(&1.id == blackboard_id))

            socket =
              socket
              |> assign(:sessions, sessions)
              |> assign(:show_delete_confirm, nil)
              |> put_flash(:info, "Session ##{blackboard_id} deleted")

            {:noreply, socket}

          {:error, _changeset} ->
            socket =
              socket
              |> assign(:show_delete_confirm, nil)
              |> put_flash(:error, "Failed to delete session")

            {:noreply, socket}
        end
    end
  end

  # PubSub handlers for real-time updates

  @impl Phoenix.LiveView
  def handle_info({:session_started, _session_id, blackboard_id}, socket) do
    {:noreply, refresh_session_in_list(socket, blackboard_id)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_paused, session_id}, socket) do
    {:noreply, update_session_status_by_session_id(socket, session_id, :paused)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_resumed, session_id}, socket) do
    {:noreply, update_session_status_by_session_id(socket, session_id, :running)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_stopped, session_id}, socket) do
    {:noreply, update_session_status_by_session_id(socket, session_id, :stopped)}
  end

  @impl Phoenix.LiveView
  def handle_info({:session_completed, session_id}, socket) do
    {:noreply, update_session_status_by_session_id(socket, session_id, :stopped)}
  end

  @impl Phoenix.LiveView
  def handle_info({:cycle_complete, _session_id, cycle_data}, socket) do
    blackboard_id = Map.get(cycle_data, :blackboard_id)

    if blackboard_id do
      {:noreply, refresh_session_in_list(socket, blackboard_id)}
    else
      {:noreply, socket}
    end
  end

  defp refresh_session_in_list(socket, blackboard_id) do
    case Repo.get(BlackboardRecord, blackboard_id) do
      nil ->
        socket

      blackboard ->
        session_statuses = get_session_statuses()
        status = determine_status(blackboard_id, session_statuses, blackboard)

        updated_session = %{
          id: blackboard.id,
          current_claim: blackboard.current_claim,
          cycle_count: blackboard.cycle_count,
          support_strength: blackboard.support_strength,
          status: status,
          inserted_at: blackboard.inserted_at
        }

        sessions = socket.assigns.sessions
        existing_index = Enum.find_index(sessions, &(&1.id == blackboard_id))

        updated_sessions =
          if existing_index do
            List.replace_at(sessions, existing_index, updated_session)
          else
            [updated_session | sessions]
          end

        assign(socket, :sessions, updated_sessions)
    end
  end

  defp update_session_status_by_session_id(socket, session_id, new_status) do
    case Session.get_info(session_id) do
      {:ok, info} ->
        blackboard_id = info.blackboard_id

        sessions =
          Enum.map(socket.assigns.sessions, fn session ->
            if session.id == blackboard_id do
              %{session | status: new_status}
            else
              session
            end
          end)

        assign(socket, :sessions, sessions)

      _ ->
        socket
    end
  end

  defp stop_session_for_blackboard(blackboard_id) do
    Session.list_sessions()
    |> Enum.each(fn {session_id, status} ->
      if status in [:running, :paused] do
        case Session.get_info(session_id) do
          {:ok, info} when info.blackboard_id == blackboard_id ->
            Session.stop(session_id)

          _ ->
            :ok
        end
      end
    end)
  rescue
    _error -> :ok
  catch
    :exit, _ -> :ok
  end

  defp empty_state(assigns) do
    ~H"""
    <.card class="text-center py-16">
      <%!-- Decorative element --%>
      <div class="w-12 h-1 bg-accent mx-auto mb-6"></div>

      <p class="font-display text-lg font-medium text-text-primary">No sessions found</p>
      <p class="mt-2 text-text-secondary text-sm font-body max-w-sm mx-auto">
        Start a new session to begin reasoning
      </p>
      <div class="mt-8">
        <a href="/sessions/new">
          <.button variant={:primary}>
            <span class="flex items-center gap-1.5">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3.5 h-3.5">
                <path d="M8 2a.75.75 0 0 1 .75.75v4.5h4.5a.75.75 0 0 1 0 1.5h-4.5v4.5a.75.75 0 0 1-1.5 0v-4.5h-4.5a.75.75 0 0 1 0-1.5h4.5v-4.5A.75.75 0 0 1 8 2Z" />
              </svg>
              Start New Session
            </span>
          </.button>
        </a>
      </div>
    </.card>
    """
  end

  attr(:sessions, :list, required: true)

  defp sessions_list(assigns) do
    ~H"""
    <div class="space-y-3">
      <div :for={{session, index} <- Enum.with_index(@sessions)} class="relative group">
        <.session_card
          id={session.id}
          claim={session.current_claim}
          cycle_count={session.cycle_count}
          support_strength={session.support_strength}
          status={session.status}
          inserted_at={session.inserted_at}
          navigate={"/sessions/#{session.id}"}
          class={"animate-fade-in stagger-#{min(index + 1, 5)}"}
        />
        <%!-- Delete button overlay --%>
        <button
          type="button"
          phx-click="show_delete_confirm"
          phx-value-id={session.id}
          class={[
            "absolute top-3 right-3 p-2",
            "bg-surface-elevated border border-border",
            "text-text-muted hover:text-status-dead hover:border-status-dead",
            "opacity-0 group-hover:opacity-100 transition-opacity",
            "z-10"
          ]}
          title="Delete session"
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-4 h-4">
            <path fill-rule="evenodd" d="M5 3.25V4H2.75a.75.75 0 0 0 0 1.5h.3l.815 8.15A1.5 1.5 0 0 0 5.357 15h5.285a1.5 1.5 0 0 0 1.493-1.35l.815-8.15h.3a.75.75 0 0 0 0-1.5H11v-.75A2.25 2.25 0 0 0 8.75 1h-1.5A2.25 2.25 0 0 0 5 3.25Zm2.25-.75a.75.75 0 0 0-.75.75V4h3v-.75a.75.75 0 0 0-.75-.75h-1.5ZM6.05 6a.75.75 0 0 1 .787.713l.275 5.5a.75.75 0 0 1-1.498.075l-.275-5.5A.75.75 0 0 1 6.05 6Zm3.9 0a.75.75 0 0 1 .712.787l-.275 5.5a.75.75 0 0 1-1.498-.075l.275-5.5a.75.75 0 0 1 .786-.711Z" clip-rule="evenodd" />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  defp list_sessions_with_status(opts) do
    page = Keyword.get(opts, :page, 0)
    page_size = Keyword.get(opts, :page_size, 10)
    offset = page * page_size

    try do
      # Get blackboard records with pagination, ordered by most recent first
      # Using ID for ordering as it's sequential and avoids timestamp precision issues
      blackboards =
        Repo.all(
          from(b in BlackboardRecord,
            order_by: [desc: b.id],
            limit: ^page_size,
            offset: ^offset
          )
        )

      # Get session statuses from the Session GenServer
      session_statuses = get_session_statuses()

      # Map blackboards to session data with status
      sessions =
        Enum.map(blackboards, fn blackboard ->
          status = determine_status(blackboard.id, session_statuses, blackboard)

          %{
            id: blackboard.id,
            current_claim: blackboard.current_claim,
            cycle_count: blackboard.cycle_count,
            support_strength: blackboard.support_strength,
            status: status,
            inserted_at: blackboard.inserted_at
          }
        end)

      # Check if there are more records
      count_result =
        Repo.one(
          from(b in BlackboardRecord,
            select: count(b.id)
          )
        )

      total_count = count_result || 0
      has_more = total_count > (page + 1) * page_size

      {:ok, sessions, has_more}
    rescue
      e in Ecto.QueryError ->
        {:error, e}

      e in DBConnection.ConnectionError ->
        {:error, e}
    catch
      :exit, reason ->
        {:error, reason}
    end
  end

  defp format_db_error(%Ecto.QueryError{}), do: "Database query failed. Please try again."

  defp format_db_error(%DBConnection.ConnectionError{}),
    do: "Database connection lost. Please try again."

  defp format_db_error({:timeout, _}), do: "Database request timed out. Please try again."
  defp format_db_error(_), do: "Failed to load sessions. Please try again."

  defp get_session_statuses do
    Session.list_sessions()
  rescue
    # Handle case where Session GenServer is not running
    _error -> []
  catch
    :exit, _ -> []
  end

  defp determine_status(blackboard_id, session_statuses, blackboard) do
    # Check if there's an active session for this blackboard
    active_status =
      Enum.find_value(session_statuses, fn {session_id, status} ->
        case Session.get_info(session_id) do
          {:ok, info} when info.blackboard_id == blackboard_id -> status
          _ -> nil
        end
      end)

    cond do
      active_status != nil ->
        active_status

      blackboard.support_strength >= 0.85 ->
        :graduated

      blackboard.support_strength <= 0.2 ->
        :dead

      true ->
        :stopped
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
end
