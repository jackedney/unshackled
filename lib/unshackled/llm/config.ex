defmodule Unshackled.LLM.Config do
  @moduledoc """
  Configuration for LLM model pool.
  """

  import Unshackled.ConfigHelpers

  defconfig(:model_pool,
    app_key: :llm,
    default: [
      "openai/gpt-5.2",
      "openai/gpt-5-nano",
      "google/gemini-3-pro-preview",
      "moonshotai/kimi-k2.5",
      "anthropic/claude-opus-4.5",
      "anthropic/claude-haiku-4.5",
      "z-ai/glm-4.7",
      "deepseek/deepseek-v3.2",
      "mistralai/mistral-large-2512"
    ]
  )

  @doc """
  Returns a random model from the pool.
  """
  @spec random_model() :: String.t()
  def random_model do
    Enum.random(model_pool())
  end

  @doc """
  Validates that a model name is in the pool.
  """
  @spec valid_model?(String.t()) :: boolean()
  def valid_model?(model) when is_binary(model) do
    Enum.member?(model_pool(), model)
  end

  def valid_model?(_), do: false

  @doc """
  Returns the OpenRouter API key from configuration.
  """
  @spec api_key() :: String.t() | no_return()
  def api_key do
    case Application.get_env(:ex_llm, :api_key) || System.get_env("OPENROUTER_API_KEY") do
      nil ->
        raise """
        OPENROUTER_API_KEY is not configured.

        Set the OPENROUTER_API_KEY environment variable or configure it in config/runtime.exs.
        """

      key ->
        key
    end
  end
end
