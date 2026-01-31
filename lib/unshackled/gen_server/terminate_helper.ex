defmodule Unshackled.GenServer.TerminateHelper do
  @moduledoc """
  Shared helper for GenServer terminate callback logging.

  Provides consistent shutdown logging across GenServers with
  appropriate log levels based on shutdown reason.
  """

  require Logger

  @doc """
  Logs shutdown information with appropriate level based on reason.

  For normal/shutdown reasons, logs at info level.
  For unexpected termination reasons, logs at warning level.

  ## Parameters

  - `module_name`: The name of the module being terminated (for logging)
  - `reason`: The termination reason
  - `cycle_count`: Current cycle count for metadata

  ## Examples

      iex> TerminateHelper.log_shutdown("Cycle.Runner", :normal, 42)
      :ok

      iex> TerminateHelper.log_shutdown("Blackboard.Server", {:error, :timeout}, 15)
      :ok
  """
  @spec log_shutdown(String.t(), term(), non_neg_integer()) :: :ok
  def log_shutdown(module_name, reason, cycle_count) do
    case reason do
      :normal ->
        Logger.info(
          metadata: [cycle_number: cycle_count],
          message: "Shutting down #{module_name} with reason: :normal (completed #{cycle_count} cycles)"
        )

      :shutdown ->
        Logger.info(
          metadata: [cycle_number: cycle_count],
          message: "Shutting down #{module_name} with reason: :shutdown (completed #{cycle_count} cycles)"
        )

      {:shutdown, _} = shutdown_reason ->
        Logger.info(
          metadata: [cycle_number: cycle_count],
          message: "Shutting down #{module_name} with reason: #{inspect(shutdown_reason)} (completed #{cycle_count} cycles)"
        )

      other_reason ->
        Logger.warning(
          metadata: [cycle_number: cycle_count],
          message: "#{module_name} terminating with reason: #{inspect(other_reason)} (completed #{cycle_count} cycles)"
        )
    end

    :ok
  end
end
