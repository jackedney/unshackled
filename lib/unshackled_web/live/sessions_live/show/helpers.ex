defmodule UnshackledWeb.SessionsLive.Show.Helpers do
  @moduledoc """
  Helper functions for SessionsLive.Show.

  This module contains private helper functions that support the LiveView
  but are not core callbacks like mount, handle_event, or handle_info.
  """

  alias Unshackled.Session
  import Phoenix.Component, only: [assign: 3]

  @doc """
  Expands all timeline nodes by creating a map with true values.
  """
  def expand_all_ids(ids) do
    Enum.reduce(ids, %{}, fn id, acc -> Map.put(acc, id, true) end)
  end

  @doc """
  Finds the session ID that owns a blackboard.

  Returns the session ID or nil if no session owns the blackboard
  or if the Session GenServer is not running.
  """
  def find_session_id_for_blackboard(blackboard_id) do
    sessions = Session.list_sessions()

    Enum.find_value(sessions, fn {session_id, _status} ->
      case Session.get_info(session_id) do
        {:ok, info} when info.blackboard_id == blackboard_id -> session_id
        _ -> nil
      end
    end)
  rescue
    _error -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Determines the status of a session based on session state and blackboard.

  First checks if there's an active session and gets its status.
  If the session is not available or has an error, infers status
  from the blackboard's support strength.
  """
  def determine_status(blackboard, session_id) do
    if session_id do
      case Session.status(session_id) do
        {:ok, status} -> status
        {:error, _} -> infer_status_from_blackboard(blackboard)
      end
    else
      infer_status_from_blackboard(blackboard)
    end
  rescue
    _error -> infer_status_from_blackboard(blackboard)
  catch
    :exit, _ -> infer_status_from_blackboard(blackboard)
  end

  @doc """
  Infers session status from blackboard support strength.

  Rules:
  - support >= 0.85 -> :graduated
  - support <= 0.2 -> :dead
  - otherwise -> :stopped
  """
  def infer_status_from_blackboard(blackboard) do
    cond do
      blackboard.support_strength >= 0.85 -> :graduated
      blackboard.support_strength <= 0.2 -> :dead
      true -> :stopped
    end
  end

  @doc """
  Updates a single field on the blackboard in the socket assigns.

  Returns {:noreply, updated_socket} for use in handle_info handlers.
  """
  def update_blackboard_field(socket, field, value) do
    blackboard = Map.put(socket.assigns.blackboard, field, value)
    {:noreply, assign(socket, :blackboard, blackboard)}
  end

  @doc """
  Assigns the current request path to the socket.

  Returns the updated socket with :current_path assigned.
  """
  def assign_current_path(socket) do
    request_path = get_request_path(socket)
    assign(socket, :current_path, request_path || "/")
  end

  @doc """
  Gets the request path from the socket's connect_info.

  Returns the path string or nil if not available.
  """
  def get_request_path(socket) do
    case socket.private[:connect_info] do
      %{request_path: path} when is_binary(path) -> path
      _ -> nil
    end
  end
end
