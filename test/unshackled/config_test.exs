defmodule Unshackled.ConfigTest do
  use ExUnit.Case
  doctest Unshackled.Config

  alias Unshackled.Config

  describe "new/1" do
    test "creates config with default values" do
      config = Config.new()

      assert config.max_cycles == 50
      assert config.cycle_mode == :event_driven
      assert config.cycle_timeout_ms == 300_000
      assert length(config.model_pool) == 7
      assert config.agent_overrides == nil
      assert config.novelty_bonus_enabled == true
      assert config.decay_rate == 0.02
    end

    test "creates config with custom seed and 50 cycles" do
      config = Config.new(seed_claim: "Custom seed claim", max_cycles: 50)

      assert config.seed_claim == "Custom seed claim"
      assert config.max_cycles == 50
    end

    test "creates config with custom cycle mode" do
      config = Config.new(cycle_mode: :time_based)

      assert config.cycle_mode == :time_based
    end

    test "creates config with custom model pool" do
      custom_pool = ["openai/gpt-5.2", "anthropic/claude-opus-4.5"]
      config = Config.new(model_pool: custom_pool)

      assert config.model_pool == custom_pool
    end

    test "creates config with agent overrides" do
      overrides = %{explorer: %{enabled: false}}
      config = Config.new(agent_overrides: overrides)

      assert config.agent_overrides == overrides
    end

    test "creates config with novelty bonus disabled" do
      config = Config.new(novelty_bonus_enabled: false)

      assert config.novelty_bonus_enabled == false
    end

    test "creates config with custom decay rate" do
      config = Config.new(decay_rate: 0.03)

      assert config.decay_rate == 0.03
    end

    test "creates config with cost limit" do
      config = Config.new(cost_limit_usd: 1.50)

      assert config.cost_limit_usd == 1.50
    end

    test "creates config with nil cost limit (default)" do
      config = Config.new()

      assert config.cost_limit_usd == nil
    end
  end

  describe "validate/1" do
    test "valid config returns ok" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)

      assert {:ok, ^config} = Config.validate(config)
    end

    test "valid config with all fields returns ok" do
      config =
        Config.new(
          seed_claim: "Test claim",
          max_cycles: 100,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 300_000,
          model_pool: ["openai/gpt-5.2"],
          agent_overrides: %{},
          novelty_bonus_enabled: true,
          decay_rate: 0.02
        )

      assert {:ok, ^config} = Config.validate(config)
    end

    test "negative case: max_cycles of -1 fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: -1)

      assert {:error, errors} = Config.validate(config)
      assert "max_cycles must be a positive integer" in errors
    end

    test "negative case: max_cycles of 0 fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 0)

      assert {:error, errors} = Config.validate(config)
      assert "max_cycles must be a positive integer" in errors
    end

    test "negative case: empty seed_claim fails validation" do
      config = Config.new(seed_claim: "", max_cycles: 50)

      assert {:error, errors} = Config.validate(config)
      assert "seed_claim cannot be empty" in errors
    end

    test "negative case: nil seed_claim fails validation" do
      config = Config.new(max_cycles: 50)

      assert {:error, errors} = Config.validate(config)
      assert "seed_claim is required" in errors
    end

    test "negative case: invalid cycle_mode fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, cycle_mode: :invalid)

      assert {:error, errors} = Config.validate(config)
      assert "cycle_mode must be :time_based or :event_driven" in errors
    end

    test "negative case: invalid cycle_timeout_ms fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, cycle_timeout_ms: -100)

      assert {:error, errors} = Config.validate(config)
      assert "cycle_timeout_ms must be a positive integer" in errors
    end

    test "negative case: empty model_pool fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, model_pool: [])

      assert {:error, errors} = Config.validate(config)
      assert "model_pool must be a non-empty list of strings" in errors
    end

    test "negative case: model_pool with non-strings fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, model_pool: [:invalid])

      assert {:error, errors} = Config.validate(config)
      assert "model_pool must be a list of strings" in errors
    end

    test "negative case: invalid agent_overrides fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, agent_overrides: "not a map")

      assert {:error, errors} = Config.validate(config)
      assert "agent_overrides must be a map if provided" in errors
    end

    test "negative case: invalid novelty_bonus_enabled fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, novelty_bonus_enabled: "yes")

      assert {:error, errors} = Config.validate(config)
      assert "novelty_bonus_enabled must be a boolean" in errors
    end

    test "negative case: invalid decay_rate fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, decay_rate: -0.01)

      assert {:error, errors} = Config.validate(config)
      assert "decay_rate must be a positive number" in errors
    end

    test "accepts nil cost_limit_usd" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, cost_limit_usd: nil)

      assert {:ok, ^config} = Config.validate(config)
    end

    test "accepts positive cost_limit_usd" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, cost_limit_usd: 1.50)

      assert {:ok, ^config} = Config.validate(config)
    end

    test "negative case: negative cost_limit_usd fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, cost_limit_usd: -1.0)

      assert {:error, errors} = Config.validate(config)
      assert "cost_limit_usd must be nil or a positive number" in errors
    end

    test "negative case: zero cost_limit_usd fails validation" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50, cost_limit_usd: 0.0)

      assert {:error, errors} = Config.validate(config)
      assert "cost_limit_usd must be nil or a positive number" in errors
    end

    test "returns multiple errors for invalid config" do
      config = Config.new(seed_claim: "", max_cycles: -1, cycle_mode: :invalid)

      assert {:error, errors} = Config.validate(config)
      assert "seed_claim cannot be empty" in errors
      assert "max_cycles must be a positive integer" in errors
      assert "cycle_mode must be :time_based or :event_driven" in errors
    end
  end

  describe "from_map/1" do
    test "parses valid map to config" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "cycle_mode" => "event_driven",
        "cycle_timeout_ms" => 300_000,
        "model_pool" => ["openai/gpt-5.2"],
        "novelty_bonus_enabled" => true,
        "decay_rate" => 0.02
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.seed_claim == "Test claim"
      assert config.max_cycles == 50
      assert config.cycle_mode == :event_driven
      assert config.cycle_timeout_ms == 300_000
    end

    test "parses map with atom keys" do
      map = %{
        seed_claim: "Test claim",
        max_cycles: 100,
        cycle_mode: "time_based"
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.seed_claim == "Test claim"
      assert config.max_cycles == 100
      assert config.cycle_mode == :time_based
    end

    test "uses defaults for missing fields" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cycle_mode == :event_driven
      assert config.cycle_timeout_ms == 300_000
      assert config.novelty_bonus_enabled == true
      assert config.decay_rate == 0.02
    end

    test "negative case: max_cycles of -1 fails validation" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => -1
      }

      assert {:error, errors} = Config.from_map(map)
      assert "max_cycles must be a positive integer" in errors
    end

    test "negative case: empty seed_claim fails validation" do
      map = %{
        "seed_claim" => "",
        "max_cycles" => 50
      }

      assert {:error, errors} = Config.from_map(map)
      assert "seed_claim cannot be empty" in errors
    end

    test "parses time_based cycle mode" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "cycle_mode" => "time_based"
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cycle_mode == :time_based
    end

    test "parses event_driven cycle mode" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "cycle_mode" => "event_driven"
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cycle_mode == :event_driven
    end

    test "defaults cycle_mode to event_driven for invalid value" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "cycle_mode" => "invalid"
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cycle_mode == :event_driven
    end

    test "parses agent_overrides from map" do
      overrides = %{"explorer" => %{"enabled" => false}}

      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "agent_overrides" => overrides
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.agent_overrides == overrides
    end

    test "parses novelty_bonus_enabled false" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "novelty_bonus_enabled" => false
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.novelty_bonus_enabled == false
    end

    test "parses custom decay_rate" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "decay_rate" => 0.03
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.decay_rate == 0.03
    end

    test "parses cost_limit_usd from map" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "cost_limit_usd" => 1.50
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cost_limit_usd == 1.50
    end

    test "parses nil cost_limit_usd when not in map" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cost_limit_usd == nil
    end

    test "parses cost_limit_usd with atom key" do
      map = %{
        seed_claim: "Test claim",
        max_cycles: 50,
        cost_limit_usd: 2.00
      }

      assert {:ok, config} = Config.from_map(map)
      assert config.cost_limit_usd == 2.00
    end

    test "negative case: negative cost_limit_usd fails validation in from_map" do
      map = %{
        "seed_claim" => "Test claim",
        "max_cycles" => 50,
        "cost_limit_usd" => -1.0
      }

      assert {:error, errors} = Config.from_map(map)
      assert "cost_limit_usd must be nil or a positive number" in errors
    end
  end

  describe "to_keyword_list/1" do
    test "converts config to keyword list" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)

      opts = Config.to_keyword_list(config)

      assert Keyword.get(opts, :seed_claim) == "Test claim"
      assert Keyword.get(opts, :max_cycles) == 50
      assert Keyword.get(opts, :cycle_mode) == :event_driven
      assert Keyword.get(opts, :cycle_timeout_ms) == 300_000
    end

    test "includes custom values" do
      config =
        Config.new(
          seed_claim: "Test claim",
          max_cycles: 100,
          cycle_mode: :time_based,
          cycle_timeout_ms: 600_000
        )

      opts = Config.to_keyword_list(config)

      assert Keyword.get(opts, :max_cycles) == 100
      assert Keyword.get(opts, :cycle_mode) == :time_based
      assert Keyword.get(opts, :cycle_timeout_ms) == 600_000
    end
  end
end
