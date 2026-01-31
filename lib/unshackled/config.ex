defmodule Unshackled.Config do
  @moduledoc """
  Configuration module for session parameters.

  This module defines the SessionConfig struct and provides functions
  for creating, validating, and parsing session configurations.

  Default values can be overridden in config/config.exs:

      config :unshackled, :session,
        max_cycles: 100,
        cycle_mode: :time_based,
        cycle_timeout_ms: 600_000
  """

  import Unshackled.ConfigHelpers

  defconfig(:max_cycles, app_key: :session, default: 50)

  defconfig(:cycle_mode, app_key: :session, default: :event_driven)

  defconfig(:cycle_timeout_ms, app_key: :session, default: 300_000)

  defconfig(:model_pool,
    app_key: :session,
    default: [
      "openai/gpt-5.2",
      "google/gemini-3-pro",
      "moonshot/kimi-k2.5-thinking",
      "anthropic/claude-opus-4.5",
      "zhipu/glm-4.7",
      "deepseek/deepseek-v3.2",
      "mistralai/mistral-large-latest"
    ]
  )

  defconfig(:novelty_bonus_enabled, app_key: :session, default: true)

  defconfig(:decay_rate, app_key: :session, default: 0.02)

  defstruct [
    :seed_claim,
    :max_cycles,
    :cycle_mode,
    :cycle_timeout_ms,
    :model_pool,
    :agent_overrides,
    :novelty_bonus_enabled,
    :decay_rate,
    :cost_limit_usd
  ]

  @type t :: %__MODULE__{
          seed_claim: String.t(),
          max_cycles: pos_integer(),
          cycle_mode: :time_based | :event_driven,
          cycle_timeout_ms: pos_integer(),
          model_pool: [String.t()],
          agent_overrides: map() | nil,
          novelty_bonus_enabled: boolean(),
          decay_rate: float(),
          cost_limit_usd: float() | nil
        }

  @type validation_error :: String.t()
  @type cycle_mode :: :time_based | :event_driven

  @doc """
  Creates a default SessionConfig.

  ## Examples

      iex> config = Unshackled.Config.new()
      iex> config.max_cycles
      50

      iex> config = Unshackled.Config.new(seed_claim: "Test claim", max_cycles: 100)
      iex> config.seed_claim
      "Test claim"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      seed_claim: Keyword.get(opts, :seed_claim),
      max_cycles: Keyword.get(opts, :max_cycles, max_cycles()),
      cycle_mode: Keyword.get(opts, :cycle_mode, cycle_mode()),
      cycle_timeout_ms: Keyword.get(opts, :cycle_timeout_ms, cycle_timeout_ms()),
      model_pool: Keyword.get(opts, :model_pool, model_pool()),
      agent_overrides: Keyword.get(opts, :agent_overrides),
      novelty_bonus_enabled: Keyword.get(opts, :novelty_bonus_enabled, novelty_bonus_enabled()),
      decay_rate: Keyword.get(opts, :decay_rate, decay_rate()),
      cost_limit_usd: Keyword.get(opts, :cost_limit_usd)
    }
  end

  @doc """
  Validates a SessionConfig.

  Returns {:ok, config} if valid, or {:error, reasons} if invalid.

  ## Validation Rules

  - `seed_claim` must be a non-empty string
  - `max_cycles` must be a positive integer
  - `cycle_mode` must be :time_based or :event_driven
  - `cycle_timeout_ms` must be a positive integer
  - `model_pool` must be a non-empty list of strings
  - `agent_overrides` must be a map if provided
  - `novelty_bonus_enabled` must be a boolean
  - `decay_rate` must be a positive float
  - `cost_limit_usd` must be nil or a positive number

  ## Examples

      iex> {:ok, config} = Unshackled.Config.new(seed_claim: "Test", max_cycles: 50) |> Unshackled.Config.validate()
      iex> config.max_cycles
      50

      iex> {:error, reasons} = Unshackled.Config.new(seed_claim: "", max_cycles: -1) |> Unshackled.Config.validate()
      iex> is_list(reasons)
      true
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate(%__MODULE__{} = config) do
    errors =
      []
      |> validate_seed_claim(config.seed_claim)
      |> validate_max_cycles(config.max_cycles)
      |> validate_cycle_mode(config.cycle_mode)
      |> validate_cycle_timeout_ms(config.cycle_timeout_ms)
      |> validate_model_pool(config.model_pool)
      |> validate_agent_overrides(config.agent_overrides)
      |> validate_novelty_bonus_enabled(config.novelty_bonus_enabled)
      |> validate_decay_rate(config.decay_rate)
      |> validate_cost_limit_usd(config.cost_limit_usd)

    case errors do
      [] -> {:ok, config}
      _ -> {:error, errors}
    end
  end

  @doc """
  Parses a configuration from a map.

  This is useful for web frontends or APIs where configuration comes from
  JSON or user input.

  ## Examples

      iex> map = %{"seed_claim" => "Test", "max_cycles" => 50, "cycle_mode" => "event_driven", "cycle_timeout_ms" => 300_000}
      iex> {:ok, config} = Unshackled.Config.from_map(map)
      iex> config.seed_claim
      "Test"

      iex> map = %{"seed_claim" => "Test", "max_cycles" => -1}
      iex> {:error, reasons} = Unshackled.Config.from_map(map)
      iex> length(reasons) > 0
      true
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, [String.t()]}
  def from_map(map) when is_map(map) do
    opts =
      []
      |> maybe_put_opt(:seed_claim, get_value(map, "seed_claim", :seed_claim))
      |> maybe_put_opt(:max_cycles, get_value(map, "max_cycles", :max_cycles))
      |> maybe_put_opt(:cycle_mode, parse_cycle_mode(get_value(map, "cycle_mode", :cycle_mode)))
      |> maybe_put_opt(:cycle_timeout_ms, get_value(map, "cycle_timeout_ms", :cycle_timeout_ms))
      |> maybe_put_opt(:model_pool, get_value(map, "model_pool", :model_pool))
      |> maybe_put_opt(:agent_overrides, get_value(map, "agent_overrides", :agent_overrides))
      |> maybe_put_opt(
        :novelty_bonus_enabled,
        get_value(map, "novelty_bonus_enabled", :novelty_bonus_enabled)
      )
      |> maybe_put_opt(:decay_rate, get_value(map, "decay_rate", :decay_rate))
      |> maybe_put_opt(:cost_limit_usd, get_value(map, "cost_limit_usd", :cost_limit_usd))

    config = new(opts)
    validate(config)
  end

  @spec get_value(map(), term(), term(), term()) :: term()
  defp get_value(map, key1, key2, default \\ nil) do
    cond do
      Map.has_key?(map, key1) -> Map.get(map, key1)
      Map.has_key?(map, key2) -> Map.get(map, key2)
      true -> default
    end
  end

  @spec maybe_put_opt(keyword(), term(), term()) :: keyword()
  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Converts the config to a keyword list suitable for GenServer start_link.

  ## Examples

      iex> config = Unshackled.Config.new(seed_claim: "Test", max_cycles: 50)
      iex> opts = Unshackled.Config.to_keyword_list(config)
      iex> Keyword.get(opts, :seed_claim)
      "Test"
  """
  @spec to_keyword_list(t()) :: keyword()
  def to_keyword_list(%__MODULE__{} = config) do
    [
      seed_claim: config.seed_claim,
      max_cycles: config.max_cycles,
      cycle_mode: config.cycle_mode,
      cycle_timeout_ms: config.cycle_timeout_ms,
      cost_limit_usd: config.cost_limit_usd
    ]
  end

  @spec parse_cycle_mode(nil | String.t() | atom()) :: cycle_mode()
  defp parse_cycle_mode(nil), do: cycle_mode()

  defp parse_cycle_mode("time_based"), do: :time_based
  defp parse_cycle_mode(:time_based), do: :time_based
  defp parse_cycle_mode("event_driven"), do: :event_driven
  defp parse_cycle_mode(:event_driven), do: :event_driven
  defp parse_cycle_mode(_), do: cycle_mode()

  @spec validate_seed_claim([validation_error()], term()) :: [validation_error()]
  defp validate_seed_claim(errors, nil),
    do: ["seed_claim is required" | errors]

  defp validate_seed_claim(errors, "") when is_binary(""),
    do: ["seed_claim cannot be empty" | errors]

  defp validate_seed_claim(errors, seed_claim) when is_binary(seed_claim),
    do: errors

  defp validate_seed_claim(errors, _), do: ["seed_claim must be a string" | errors]

  @spec validate_max_cycles([validation_error()], term()) :: [validation_error()]
  defp validate_max_cycles(errors, max_cycles) when is_integer(max_cycles) and max_cycles > 0,
    do: errors

  defp validate_max_cycles(errors, _), do: ["max_cycles must be a positive integer" | errors]

  @spec validate_cycle_mode([validation_error()], term()) :: [validation_error()]
  defp validate_cycle_mode(errors, cycle_mode) when cycle_mode in [:time_based, :event_driven],
    do: errors

  defp validate_cycle_mode(errors, _),
    do: ["cycle_mode must be :time_based or :event_driven" | errors]

  @spec validate_cycle_timeout_ms([validation_error()], term()) :: [validation_error()]
  defp validate_cycle_timeout_ms(errors, timeout) when is_integer(timeout) and timeout > 0,
    do: errors

  defp validate_cycle_timeout_ms(errors, nil), do: errors

  defp validate_cycle_timeout_ms(errors, _),
    do: ["cycle_timeout_ms must be a positive integer" | errors]

  @spec validate_model_pool([validation_error()], term()) :: [validation_error()]
  defp validate_model_pool(errors, model_pool)
       when is_list(model_pool) and length(model_pool) > 0 do
    if Enum.all?(model_pool, &is_binary/1) do
      errors
    else
      ["model_pool must be a list of strings" | errors]
    end
  end

  defp validate_model_pool(errors, nil), do: errors

  defp validate_model_pool(errors, _),
    do: ["model_pool must be a non-empty list of strings" | errors]

  @spec validate_agent_overrides([validation_error()], term()) :: [validation_error()]
  defp validate_agent_overrides(errors, nil), do: errors
  defp validate_agent_overrides(errors, agent_overrides) when is_map(agent_overrides), do: errors

  defp validate_agent_overrides(errors, _),
    do: ["agent_overrides must be a map if provided" | errors]

  @spec validate_novelty_bonus_enabled([validation_error()], term()) :: [validation_error()]
  defp validate_novelty_bonus_enabled(errors, enabled) when is_boolean(enabled), do: errors

  defp validate_novelty_bonus_enabled(errors, nil), do: errors

  defp validate_novelty_bonus_enabled(errors, _),
    do: ["novelty_bonus_enabled must be a boolean" | errors]

  @spec validate_decay_rate([validation_error()], term()) :: [validation_error()]
  defp validate_decay_rate(errors, rate) when is_number(rate) and rate > 0, do: errors

  defp validate_decay_rate(errors, nil), do: errors

  defp validate_decay_rate(errors, _), do: ["decay_rate must be a positive number" | errors]

  @spec validate_cost_limit_usd([validation_error()], term()) :: [validation_error()]
  defp validate_cost_limit_usd(errors, nil), do: errors

  defp validate_cost_limit_usd(errors, limit) when is_number(limit) and limit > 0, do: errors

  defp validate_cost_limit_usd(errors, _),
    do: ["cost_limit_usd must be nil or a positive number" | errors]
end
