defmodule Unshackled.Evolution.Config do
  @moduledoc """
  Configuration for evolution tracking parameters.

  This module provides access to evolution-related configuration values
  with fallback defaults. All values can be overridden in config/config.exs.
  """

  import Unshackled.ConfigHelpers

  defconfig(:similarity_threshold, app_key: :evolution, default: 0.95)

  defconfig(:summarizer_debounce_cycles, app_key: :evolution, default: 0)

  defconfig(:summarizer_model, app_key: :evolution, default: "anthropic/claude-haiku-4.5")
end
