defmodule Unshackled.Embedding.ModelServer do
  @moduledoc """
  GenServer that loads and manages the sentence-transformers embedding model.

  Loads the all-MiniLM-L6-v2 model via Bumblebee at application startup
  and provides APIs for computing semantic embeddings.

  The model produces 384-dimensional embeddings that are L2-normalized.
  """

  use GenServer
  require Logger

  @model_repo "sentence-transformers/all-MiniLM-L6-v2"
  @embedding_dim 384

  defstruct [:serving, :ready]

  @type t :: %__MODULE__{
          serving: Nx.Serving.t() | nil,
          ready: boolean()
        }

  @doc """
  Starts the ModelServer GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Embeds a single text string.

  Returns {:ok, tensor} with a 384-dim L2-normalized tensor,
  or {:error, reason} if the model is not ready.
  """
  @spec embed(String.t()) :: {:ok, Nx.Tensor.t()} | {:error, atom()}
  def embed(text) when is_binary(text) do
    GenServer.call(__MODULE__, {:embed, text}, :infinity)
  end

  @doc """
  Embeds a batch of text strings.

  Returns {:ok, tensor} with shape {batch_size, 384},
  or {:error, reason} if the model is not ready.
  """
  @spec embed_batch([String.t()]) :: {:ok, Nx.Tensor.t()} | {:error, atom()}
  def embed_batch(texts) when is_list(texts) do
    GenServer.call(__MODULE__, {:embed_batch, texts}, :infinity)
  end

  @doc """
  Checks if the model is ready for inference.
  """
  @spec ready?() :: boolean()
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end

  @doc """
  Returns the embedding dimension (384 for all-MiniLM-L6-v2).
  """
  @spec embedding_dim() :: pos_integer()
  def embedding_dim, do: @embedding_dim

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{serving: nil, ready: false}, {:continue, :load_model}}
  end

  @impl GenServer
  def handle_continue(:load_model, state) do
    case load_model() do
      {:ok, serving} ->
        Logger.info("Embedding model loaded successfully (#{@model_repo})")
        {:noreply, %{state | serving: serving, ready: true}}

      {:error, reason} ->
        Logger.warning("Failed to load embedding model: #{inspect(reason)}")
        {:noreply, %{state | serving: nil, ready: false}}
    end
  end

  @impl GenServer
  def handle_call({:embed, _text}, _from, %{ready: false} = state) do
    {:reply, {:error, :model_not_ready}, state}
  end

  def handle_call({:embed, text}, _from, %{serving: serving} = state) do
    result = compute_embedding(serving, text)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:embed_batch, _texts}, _from, %{ready: false} = state) do
    {:reply, {:error, :model_not_ready}, state}
  end

  def handle_call({:embed_batch, texts}, _from, %{serving: serving} = state) do
    result = compute_batch_embedding(serving, texts)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:ready?, _from, state) do
    {:reply, state.ready, state}
  end

  # Private functions

  # Loads the Bumblebee model and tokenizer, returning a configured serving.
  #
  # This function uses try/rescue because Bumblebee.load_model/1 and
  # Bumblebee.load_tokenizer/1 are external API calls that may raise
  # exceptions on model download failures, memory constraints, or dependency issues.
  # The exceptions are caught and logged, returning {:error, reason} instead of crashing.
  defp load_model do
    try do
      Logger.info("Loading embedding model: #{@model_repo}")

      {:ok, model_info} = Bumblebee.load_model({:hf, @model_repo})
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @model_repo})

      serving =
        Bumblebee.Text.TextEmbedding.text_embedding(model_info, tokenizer,
          compile: [batch_size: 8, sequence_length: 128],
          defn_options: [compiler: EXLA],
          output_pool: :mean_pooling,
          output_attribute: :hidden_state
        )

      {:ok, serving}
    rescue
      e ->
        Logger.error("Error loading model: #{Exception.message(e)}")
        {:error, e}
    end
  end

  # Computes L2-normalized embedding for a single text.
  #
  # This function uses try/rescue because Nx.Serving.run/2 is an external
  # API that may raise exceptions on invalid input, model errors, or resource
  # exhaustion. The exception is caught and logged, returning {:error, reason}
  # instead of crashing the calling process.
  defp compute_embedding(serving, text) do
    try do
      %{embedding: embedding} = Nx.Serving.run(serving, text)
      normalized = l2_normalize(embedding)
      {:ok, normalized}
    rescue
      e ->
        Logger.error("Error computing embedding: #{Exception.message(e)}")
        {:error, e}
    end
  end

  # Computes L2-normalized embeddings for a batch of text strings.
  #
  # This function uses try/rescue because Nx.Serving.run/2 is an external
  # API that may raise exceptions on invalid input, model errors, or resource
  # exhaustion. The exception is caught and logged, returning {:error, reason}
  # instead of crashing the calling process.
  defp compute_batch_embedding(serving, texts) do
    try do
      results = Nx.Serving.run(serving, Nx.Batch.concatenate(Enum.map(texts, &%{text: &1})))
      embeddings = results.embedding
      normalized = l2_normalize(embeddings)
      {:ok, normalized}
    rescue
      e ->
        Logger.error("Error computing batch embedding: #{Exception.message(e)}")
        {:error, e}
    end
  end

  defp l2_normalize(tensor) do
    norms = Nx.sqrt(Nx.sum(Nx.pow(tensor, 2), axes: [-1], keep_axes: true))
    Nx.divide(tensor, Nx.max(norms, 1.0e-12))
  end
end
