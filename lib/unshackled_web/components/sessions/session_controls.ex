defmodule UnshackledWeb.Components.Sessions.SessionControls do
  @moduledoc """
  Component for displaying session control buttons and confirmation dialogs.

  Renders action buttons for session management (pause, resume, stop, delete)
  based on the current session status, with confirmation dialogs for destructive actions.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import UnshackledWeb.CoreComponents

  @doc """
  Renders session control buttons with appropriate state based on session status.

  ## Attributes

  * `session_id` - The session ID (required)
  * `status` - Current session status atom (required)
  * `blackboard_id` - The blackboard record ID (required)
  * `show_stop_confirm` - Whether to show stop confirmation dialog (optional, defaults to false)
  * `show_delete_confirm` - Whether to show delete confirmation dialog (optional, defaults to false)

  ## Examples

      <.session_controls
        session_id={@session_id}
        status={@status}
        blackboard_id={@blackboard.id}
        show_stop_confirm={@show_stop_confirm}
        show_delete_confirm={@show_delete_confirm}
      />

  ## Behavior

  * Shows "Pause" button when status is :running
  * Shows "Resume" button when status is :paused
  * Shows "Stop" button when status is :running or :paused
  * Shows "Delete" button when status is :stopped, :completed, :graduated, or :dead
  """
  attr(:session_id, :string, required: true, doc: "the session ID")
  attr(:status, :atom, required: true, doc: "current session status atom")
  attr(:blackboard_id, :integer, required: true, doc: "the blackboard record ID")

  attr(:show_stop_confirm, :boolean,
    default: false,
    doc: "whether to show stop confirmation dialog"
  )

  attr(:show_delete_confirm, :boolean,
    default: false,
    doc: "whether to show delete confirmation dialog"
  )

  def session_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%!-- Pause button: visible when running --%>
      <%= if @session_id && @status == :running do %>
        <.button phx-click="pause_session" variant={:secondary}>
          Pause
        </.button>
      <% end %>

      <%!-- Resume button: visible when paused --%>
      <%= if @session_id && @status == :paused do %>
        <.button phx-click="resume_session" variant={:primary}>
          Resume
        </.button>
      <% end %>

      <%!-- Stop button: visible for active sessions (running or paused) --%>
      <%= if @session_id && @status in [:running, :paused] do %>
        <.button phx-click="show_stop_confirm" variant={:danger}>
          Stop
        </.button>
      <% end %>

      <%!-- Delete button: always visible for stopped/completed/graduated/dead sessions --%>
      <%= if @status in [:stopped, :completed, :graduated, :dead] do %>
        <.button phx-click="show_delete_confirm" variant={:danger}>
          <span class="flex items-center gap-1.5">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="w-3.5 h-3.5">
              <path fill-rule="evenodd" d="M5 3.25V4H2.75a.75.75 0 0 0 0 1.5h.3l.815 8.15A1.5 1.5 0 0 0 5.357 15h5.285a1.5 1.5 0 0 0 1.493-1.35l.815-8.15h.3a.75.75 0 0 0 0-1.5H11v-.75A2.25 2.25 0 0 0 8.75 1h-1.5A2.25 2.25 0 0 0 5 3.25Zm2.25-.75a.75.75 0 0 0-.75.75V4h3v-.75a.75.75 0 0 0-.75-.75h-1.5ZM6.05 6a.75.75 0 0 1 .787.713l.275 5.5a.75.75 0 0 1-1.498.075l-.275-5.5A.75.75 0 0 1 6.05 6Zm3.9 0a.75.75 0 0 1 .712.787l-.275 5.5a.75.75 0 0 1-1.498-.075l.275-5.5a.75.75 0 0 1 .786-.711Z" clip-rule="evenodd" />
            </svg>
            Delete
          </span>
        </.button>
      <% end %>

      <%!-- Stop confirmation modal --%>
      <.modal
        id="stop-confirm-modal"
        show={@show_stop_confirm}
        on_close={JS.push("cancel_stop")}
        class="border-status-dead"
      >
        <:title>
          <span class="text-status-dead">Confirm Stop</span>
        </:title>
        <p>
          Are you sure you want to stop this session? This action cannot be undone.
          The session will be terminated and no further cycles will run.
        </p>
        <:actions>
          <.button phx-click="cancel_stop" variant={:secondary}>
            Cancel
          </.button>
          <.button phx-click="confirm_stop" variant={:danger}>
            Stop Session
          </.button>
        </:actions>
      </.modal>

      <%!-- Delete confirmation modal --%>
      <.modal
        id="delete-confirm-modal"
        show={@show_delete_confirm}
        on_close={JS.push("cancel_delete")}
        class="border-status-dead"
      >
        <:title>
          <span class="text-status-dead">Delete Session</span>
        </:title>
        <p class="mb-4">
          Are you sure you want to delete <strong>Session #<%= @blackboard_id %></strong>?
        </p>
        <p class="text-status-dead font-bold">
          This action cannot be undone. All session data will be permanently deleted.
        </p>
        <:actions>
          <.button phx-click="cancel_delete" variant={:secondary}>
            Cancel
          </.button>
          <.button phx-click="confirm_delete" variant={:danger}>
            Delete Session
          </.button>
        </:actions>
      </.modal>
    </div>
    """
  end
end
