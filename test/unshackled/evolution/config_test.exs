defmodule Unshackled.Evolution.ConfigTest do
  use ExUnit.Case
  doctest Unshackled.Evolution.Config

  alias Unshackled.Evolution.Config

  describe "similarity_threshold/0" do
    test "returns default value when not configured" do
      assert Config.similarity_threshold() == 0.95
    end

    test "returns configured value when set in config" do
      Application.put_env(:unshackled, :evolution, similarity_threshold: 0.90)

      assert Config.similarity_threshold() == 0.90

      Application.put_env(:unshackled, :evolution, [])
    end
  end

  describe "summarizer_debounce_cycles/0" do
    test "returns default value when not configured" do
      assert Config.summarizer_debounce_cycles() == 0
    end

    test "returns configured value when set in config" do
      Application.put_env(:unshackled, :evolution, summarizer_debounce_cycles: 5)

      assert Config.summarizer_debounce_cycles() == 5

      Application.put_env(:unshackled, :evolution, [])
    end
  end

  describe "summarizer_model/0" do
    test "returns default value when not configured" do
      assert Config.summarizer_model() == "anthropic/claude-haiku-4.5"
    end

    test "returns configured value when set in config" do
      Application.put_env(:unshackled, :evolution, summarizer_model: "openai/gpt-3.5-turbo")

      assert Config.summarizer_model() == "openai/gpt-3.5-turbo"

      Application.put_env(:unshackled, :evolution, [])
    end
  end

  describe "negative cases" do
    test "missing config key returns default value" do
      Application.put_env(:unshackled, :evolution, [])

      assert Config.similarity_threshold() == 0.95
      assert Config.summarizer_debounce_cycles() == 0
      assert Config.summarizer_model() == "anthropic/claude-haiku-4.5"
    end

    test "partial config returns defaults for missing keys" do
      Application.put_env(:unshackled, :evolution, similarity_threshold: 0.85)

      assert Config.similarity_threshold() == 0.85
      assert Config.summarizer_debounce_cycles() == 0
      assert Config.summarizer_model() == "anthropic/claude-haiku-4.5"

      Application.put_env(:unshackled, :evolution, [])
    end

    test "does not crash when :unshackled app env is completely missing" do
      Application.delete_env(:unshackled, :evolution)

      assert Config.similarity_threshold() == 0.95
      assert Config.summarizer_debounce_cycles() == 0
      assert Config.summarizer_model() == "anthropic/claude-haiku-4.5"
    end
  end
end
