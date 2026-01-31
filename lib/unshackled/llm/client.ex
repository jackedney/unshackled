defmodule Unshackled.LLM.Client do
  @moduledoc """
  Wrapper for ExLLM calls to OpenRouter.
  """

  @behaviour Unshackled.LLM.ClientBehaviour

  alias Unshackled.LLM.Config

  @doc """
  Calls the LLM with a model and a list of messages.

  ## Parameters

  - model: String model name (e.g., "openai/gpt-5.2")
  - messages: List of message maps with :role and :content keys

  ## Returns

  - {:ok, response} on success
  - {:error, reason} on failure

  ## Examples

      iex> messages = [%{role: "user", content: "Hello"}]
      iex> {:ok, response} = Client.chat("openai/gpt-5.2", messages)
  """
  @spec chat(String.t(), [map()]) :: {:ok, map()} | {:error, term()}
  def chat(model, messages) when is_binary(model) and is_list(messages) do
    client_module = get_client_module()

    if client_module == __MODULE__ do
      chat_direct(model, messages)
    else
      chat_via_client(client_module, model, messages)
    end
  end

  def chat(_model, _messages) do
    {:error, :invalid_model}
  end

  @doc """
  Calls the LLM with a random model from the pool.

  ## Parameters

  - messages: List of message maps with :role and :content keys

  ## Returns

  - {:ok, response, model_used} on success
  - {:error, reason} on failure
  """
  @spec chat_random([map()]) :: {:ok, map(), String.t()} | {:error, term()}
  def chat_random(messages) when is_list(messages) do
    client_module = get_client_module()
    model = Config.random_model()

    case client_module.chat(model, messages) do
      {:ok, response} -> {:ok, response, model}
      error -> error
    end
  end

  @doc """
  Gets the configured LLM client module.
  Allows injection of mock clients for testing.
  """
  @spec get_client_module() :: module()
  def get_client_module do
    Application.get_env(:unshackled, :llm_client, __MODULE__)
  end

  defp chat_direct(model, messages) do
    with :ok <- validate_model(model),
         :ok <- validate_messages(messages),
         :ok <- ensure_api_key(),
         {:ok, response} <-
           ExLLM.chat(:openrouter, messages, model: model, validate_context: false) do
      {:ok, response}
    end
  end

  defp chat_via_client(client_module, model, messages) do
    with :ok <- validate_model(model),
         :ok <- validate_messages(messages),
         {:ok, response} <- client_module.chat(model, messages) do
      {:ok, response}
    end
  end

  defp validate_model(model) when is_binary(model) do
    if Config.valid_model?(model) do
      :ok
    else
      {:error, :invalid_model}
    end
  end

  defp validate_messages([]) do
    {:error, :empty_messages}
  end

  defp validate_messages(messages) do
    valid? =
      Enum.all?(messages, fn msg ->
        is_map(msg) and
          is_binary(Map.get(msg, :role)) and
          is_binary(Map.get(msg, :content))
      end)

    if valid? do
      :ok
    else
      {:error, :invalid_messages}
    end
  end

  defp ensure_api_key do
    _ = Config.api_key()
    :ok
  rescue
    _ -> {:error, :missing_api_key}
  end
end
