defmodule UnshackledWeb.SessionsLive.New do
  @moduledoc """
  New session LiveView - configuration form to start a new reasoning session.
  """
  use UnshackledWeb, :live_view_minimal

  alias Unshackled.Config
  alias Unshackled.Session

  @default_model_pool [
    "openai/gpt-5.2",
    "google/gemini-3-pro",
    "moonshot/kimi-k2.5-thinking",
    "anthropic/claude-opus-4.5",
    "zhipu/glm-4.7",
    "deepseek/deepseek-v3.2",
    "mistralai/mistral-large-latest"
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket = assign_current_path(socket)
    form_data = default_form_data()

    socket =
      socket
      |> assign(:form, to_form(form_data, as: "config"))
      |> assign(:errors, %{})
      |> assign(:model_pool_options, model_pool_options())
      |> assign(:selected_models, @default_model_pool)
      |> assign(:loading, false)
      |> assign(:status, nil)
      |> assign(:connected, connected?(socket))

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.loading_overlay :if={@loading} message="Starting session..." />

      <%!-- Connection status indicator - refined --%>
      <div class="flex items-center gap-2">
        <div class={[
          "w-1.5 h-1.5 rounded-full",
          @connected && "bg-status-active",
          !@connected && "bg-status-dead animate-pulse"
        ]} />
        <span class={["font-display text-[0.6875rem] uppercase tracking-wider", @connected && "text-text-muted" || "text-status-dead"]}>
          <%= if @connected, do: "Connected", else: "Disconnected" %>
        </span>
      </div>

      <%!-- Status message for debugging - refined --%>
      <div :if={@status} class={[
        "p-4 border text-sm font-mono relative",
        @status.type == :info && "bg-status-graduated/5 border-status-graduated/30 text-status-graduated",
        @status.type == :success && "bg-status-active/5 border-status-active/30 text-status-active",
        @status.type == :error && "bg-status-dead/5 border-status-dead/30 text-status-dead"
      ]}>
        <div class={[
          "absolute left-0 top-0 bottom-0 w-1",
          @status.type == :info && "bg-status-graduated",
          @status.type == :success && "bg-status-active",
          @status.type == :error && "bg-status-dead"
        ]}></div>
        <div class="pl-3"><%= @status.message %></div>
      </div>

      <.breadcrumb>
        <:item navigate="/sessions">Sessions</:item>
        <:item>New Session</:item>
      </.breadcrumb>

      <.header>
        New Session
        <:subtitle>Configure and start a new reasoning session</:subtitle>
      </.header>

      <.card>
        <.simple_form for={@form} phx-change="validate" phx-submit="save">
          <div class="space-y-8">
            <%!-- Seed Claim Section --%>
            <div>
              <label for="config_seed_claim" class="block font-display text-xs font-semibold uppercase tracking-wider text-text-secondary mb-3">
                Seed Claim
              </label>
              <textarea
                id="config_seed_claim"
                name="config[seed_claim]"
                class={[
                  "block w-full bg-surface border border-border px-4 py-3 text-text-primary font-body",
                  "placeholder:text-text-muted focus-brutal min-h-[120px] leading-relaxed",
                  "hover:border-border-strong transition-colors",
                  @errors[:seed_claim] && "border-status-dead"
                ]}
                placeholder="Enter the initial claim to reason about..."
                required
              ><%= @form[:seed_claim].value %></textarea>
              <.error :for={msg <- List.wrap(@errors[:seed_claim])}><%= msg %></.error>
            </div>

            <%!-- Configuration Grid --%>
            <div>
              <div class="flex items-center gap-3 mb-4">
                <span class="font-display text-xs font-semibold uppercase tracking-wider text-text-secondary">Configuration</span>
                <div class="flex-1 h-px bg-border"></div>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
                <.input
                  field={@form[:max_cycles]}
                  type="number"
                  label="Max Cycles"
                  min="1"
                  max="1000"
                  errors={List.wrap(@errors[:max_cycles])}
                />

                <.input
                  field={@form[:cycle_mode]}
                  type="select"
                  label="Cycle Mode"
                  options={[{"Event Driven", "event_driven"}, {"Time Based", "time_based"}]}
                  errors={List.wrap(@errors[:cycle_mode])}
                />

                <.input
                  field={@form[:cycle_timeout_ms]}
                  type="number"
                  label="Cycle Timeout (ms)"
                  min="1000"
                  max="3600000"
                  errors={List.wrap(@errors[:cycle_timeout_ms])}
                />

                <.input
                  field={@form[:decay_rate]}
                  type="number"
                  label="Decay Rate"
                  step="0.01"
                  min="0.001"
                  max="1.0"
                  errors={List.wrap(@errors[:decay_rate])}
                />

                <.input
                  field={@form[:cost_limit_usd]}
                  type="number"
                  label="Cost Limit (USD)"
                  step="0.01"
                  min="0"
                  placeholder="No limit"
                  errors={List.wrap(@errors[:cost_limit_usd])}
                />
              </div>
            </div>

            <%!-- Options --%>
            <div>
              <.input
                field={@form[:novelty_bonus_enabled]}
                type="checkbox"
                label="Enable Novelty Bonus"
              />
            </div>

            <%!-- Model Pool Section --%>
            <div>
              <div class="flex items-center gap-3 mb-4">
                <span class="font-display text-xs font-semibold uppercase tracking-wider text-text-secondary">Model Pool</span>
                <div class="flex-1 h-px bg-border"></div>
              </div>
              <p class="text-xs text-text-muted mb-4 font-body">
                Select the models to use for reasoning agents
              </p>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
                <label
                  :for={{label, value} <- @model_pool_options}
                  class="group flex items-center gap-3 text-sm cursor-pointer p-3 border border-border hover:border-accent hover:bg-surface-elevated transition-all"
                >
                  <input
                    type="checkbox"
                    name="config[model_pool][]"
                    value={value}
                    checked={value in @selected_models}
                    class="h-4 w-4 border border-border-strong bg-surface text-accent accent-accent"
                  />
                  <span class="text-text-secondary font-mono-data text-xs group-hover:text-text-primary transition-colors"><%= label %></span>
                </label>
              </div>
              <.error :for={msg <- List.wrap(@errors[:model_pool])}><%= msg %></.error>
            </div>
          </div>

          <:actions>
            <.link navigate="/sessions" class="inline-block">
              <.button type="button" variant={:secondary} disabled={@loading}>Cancel</.button>
            </.link>
            <.button type="submit" variant={:primary} disabled={@loading || not @connected}>
              <%= if @loading do %>
                <span class="flex items-center gap-2">
                  <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Starting...
                </span>
              <% else %>
                Start Session
              <% end %>
            </.button>
          </:actions>
        </.simple_form>
      </.card>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"config" => params}, socket) do
    # Update selected models from params
    selected_models = Map.get(params, "model_pool", [])

    # Validate and update form
    errors = validate_params(params)

    socket =
      socket
      |> assign(:form, to_form(params, as: "config"))
      |> assign(:errors, errors)
      |> assign(:selected_models, selected_models)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"config" => params}, socket) do
    # Update status to show form was submitted
    socket =
      assign(socket, :status, %{type: :info, message: "Form submitted, validating config..."})

    # Build config from params
    config_params = build_config_params(params)

    case Config.from_map(config_params) do
      {:ok, config} ->
        # Set loading state before starting session
        socket =
          socket
          |> assign(:loading, true)
          |> assign(:status, %{type: :info, message: "Config valid, starting session..."})

        # Try to start the session with timeout handling
        try do
          case Session.start(config) do
            {:ok, session_id} ->
              socket =
                assign(socket, :status, %{
                  type: :success,
                  message: "Session started! ID: #{session_id}"
                })

              # Get the blackboard_id from the session info
              case Session.get_info(session_id) do
                {:ok, info} ->
                  {:noreply,
                   socket
                   |> assign(:loading, false)
                   |> put_flash(:info, "Session started successfully")
                   |> push_navigate(to: "/sessions/#{info.blackboard_id}")}

                {:error, _} ->
                  {:noreply,
                   socket
                   |> assign(:loading, false)
                   |> put_flash(:info, "Session started successfully")
                   |> push_navigate(to: "/sessions")}
              end

            {:error, reason} ->
              {:noreply,
               socket
               |> assign(:loading, false)
               |> assign(:status, %{
                 type: :error,
                 message: "Session.start failed: #{inspect(reason)}"
               })
               |> put_flash(:error, format_error(reason))}
          end
        catch
          :exit, {:timeout, _} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:status, %{type: :error, message: "Timeout while starting session"})
             |> put_flash(:error, "Request timed out. Please try again.")}

          :exit, reason ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:status, %{
               type: :error,
               message: "Exit: #{inspect(reason)}"
             })
             |> put_flash(:error, "Service unavailable: #{format_error(reason)}")}
        end

      {:error, errors} ->
        error_map = errors_to_map(errors)

        socket =
          socket
          |> assign(:form, to_form(params, as: "config"))
          |> assign(:errors, error_map)
          |> assign(:selected_models, Map.get(params, "model_pool", []))
          |> assign(:status, %{
            type: :error,
            message: "Config validation failed: #{inspect(errors)}"
          })

        {:noreply, socket}
    end
  end

  defp format_error(:timeout), do: "Request timed out. Please try again."
  defp format_error({:timeout, _}), do: "Request timed out. Please try again."
  defp format_error(:noproc), do: "Service is not available. Please try again."
  defp format_error({:noproc, _}), do: "Service is not available. Please try again."

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error(reason) do
    "An error occurred: #{inspect(reason)}"
  end

  defp default_form_data do
    %{
      "seed_claim" => "",
      "max_cycles" => "50",
      "cycle_mode" => "event_driven",
      "cycle_timeout_ms" => "300000",
      "decay_rate" => "0.02",
      "novelty_bonus_enabled" => "true",
      "cost_limit_usd" => "",
      "model_pool" => @default_model_pool
    }
  end

  defp validate_params(params) do
    errors = %{}

    errors =
      case Map.get(params, "seed_claim", "") do
        "" ->
          Map.put(errors, :seed_claim, "is required")

        claim when is_binary(claim) and byte_size(claim) < 1 ->
          Map.put(errors, :seed_claim, "is required")

        _ ->
          errors
      end

    errors =
      case parse_integer(Map.get(params, "max_cycles"), nil) do
        nil -> errors
        n when n <= 0 -> Map.put(errors, :max_cycles, "must be a positive integer")
        _ -> errors
      end

    errors =
      case parse_integer(Map.get(params, "cycle_timeout_ms"), nil) do
        nil -> errors
        n when n <= 0 -> Map.put(errors, :cycle_timeout_ms, "must be a positive integer")
        _ -> errors
      end

    errors =
      case parse_float(Map.get(params, "decay_rate"), nil) do
        nil -> errors
        n when n <= 0 -> Map.put(errors, :decay_rate, "must be a positive number")
        _ -> errors
      end

    errors =
      case parse_optional_float(Map.get(params, "cost_limit_usd")) do
        nil -> errors
        n when n < 0 -> Map.put(errors, :cost_limit_usd, "must be a non-negative number")
        _ -> errors
      end

    errors
  end

  defp build_config_params(params) do
    # Convert form params to the format expected by Config.from_map
    model_pool = Map.get(params, "model_pool", @default_model_pool)

    # Ensure model_pool is a list (checkbox groups can sometimes be empty)
    model_pool =
      case model_pool do
        list when is_list(list) and list != [] -> list
        _ -> @default_model_pool
      end

    %{
      "seed_claim" => Map.get(params, "seed_claim"),
      "max_cycles" => parse_integer(Map.get(params, "max_cycles"), 50),
      "cycle_mode" => Map.get(params, "cycle_mode", "event_driven"),
      "cycle_timeout_ms" => parse_integer(Map.get(params, "cycle_timeout_ms"), 300_000),
      "decay_rate" => parse_float(Map.get(params, "decay_rate"), 0.02),
      "novelty_bonus_enabled" => parse_boolean(Map.get(params, "novelty_bonus_enabled")),
      "cost_limit_usd" => parse_optional_float(Map.get(params, "cost_limit_usd")),
      "model_pool" => model_pool
    }
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(value, _default) when is_integer(value), do: value
  defp parse_integer(_, default), do: default

  defp parse_float(nil, default), do: default
  defp parse_float("", default), do: default

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end

  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value * 1.0
  defp parse_float(_, default), do: default

  defp parse_optional_float(nil), do: nil
  defp parse_optional_float(""), do: nil

  defp parse_optional_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_optional_float(value) when is_float(value), do: value
  defp parse_optional_float(value) when is_integer(value), do: value * 1.0
  defp parse_optional_float(_), do: nil

  defp parse_boolean("true"), do: true
  defp parse_boolean(true), do: true
  defp parse_boolean(_), do: false

  defp errors_to_map(errors) when is_list(errors) do
    Enum.reduce(errors, %{}, fn error, acc ->
      field = error_to_field(error)
      Map.put(acc, field, error)
    end)
  end

  defp error_to_field(error) when is_binary(error) do
    cond do
      String.contains?(error, "seed_claim") -> :seed_claim
      String.contains?(error, "max_cycles") -> :max_cycles
      String.contains?(error, "cycle_mode") -> :cycle_mode
      String.contains?(error, "cycle_timeout") -> :cycle_timeout_ms
      String.contains?(error, "decay_rate") -> :decay_rate
      String.contains?(error, "novelty") -> :novelty_bonus_enabled
      String.contains?(error, "cost_limit") -> :cost_limit_usd
      String.contains?(error, "model_pool") -> :model_pool
      true -> :base
    end
  end

  defp model_pool_options do
    @default_model_pool
    |> Enum.map(fn model ->
      # Create a friendly label from model name
      label =
        model
        |> String.split("/")
        |> List.last()
        |> String.replace("-", " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      {label, model}
    end)
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
