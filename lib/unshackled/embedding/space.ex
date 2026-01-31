defmodule Unshackled.Embedding.Space do
  @moduledoc """
  GenServer managing embeddings and trajectory analysis.

  This GenServer provides:
  - ETS-based caching of embeddings for fast lookup
  - Computing embeddings from claim text and blackboard state
  - Persisting trajectory points to database
  - Retrieving trajectory history for analysis

  Embeddings are 768-dimensional tensors represented as Nx tensors.
  """

  use GenServer
  import Ecto.Query
  require Logger

  alias Unshackled.Blackboard.Server
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Repo

  @ets_table_name :embedding_cache

  defstruct [:ets_table]

  @type t :: %__MODULE__{
          ets_table: :ets.tid() | nil
        }

  @doc """
  Starts the EmbeddingSpace GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Computes embedding for a blackboard state.
  """
  @spec embed_state(Server.t()) :: {:ok, Nx.Tensor.t()} | {:error, String.t()}
  def embed_state(state) do
    GenServer.call(__MODULE__, {:embed_state, state})
  end

  @doc """
  Computes embedding for a claim text.
  """
  @spec embed_claim(String.t()) :: {:ok, Nx.Tensor.t()} | {:error, String.t()}
  def embed_claim(claim_text) do
    GenServer.call(__MODULE__, {:embed_claim, claim_text})
  end

  @doc """
  Stores a trajectory point to the database.
  """
  @spec store_trajectory_point(map()) :: {:ok, TrajectoryPoint.t()} | {:error, Ecto.Changeset.t()}
  def store_trajectory_point(point) do
    GenServer.call(__MODULE__, {:store_trajectory_point, point})
  end

  @doc """
  Retrieves trajectory points for a blackboard.
  """
  @spec get_trajectory(integer()) :: {:ok, list(TrajectoryPoint.t())} | {:error, String.t()}
  def get_trajectory(blackboard_id) when is_integer(blackboard_id) and blackboard_id > 0 do
    GenServer.call(__MODULE__, {:get_trajectory, blackboard_id})
  end

  def get_trajectory(_) do
    {:ok, []}
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{ets_table: nil}, {:continue, :setup_ets}}
  end

  @doc """
  Handles asynchronous setup after init/1 returns.

  Creates the ETS table for caching embeddings. This is done in handle_continue/2
  rather than init/1 so that GenServer.start_link/3 returns immediately and
  expensive operations happen asynchronously.

  If ETS table creation fails, the GenServer will stop with a descriptive error.

  This function uses try/rescue because :ets.new/2 is an Erlang BIF
  (built-in function) that raises ArgumentError if a table with the same name
  already exists. The exception is caught and converted to an error tuple to
  allow graceful shutdown rather than crashing.
  """
  @impl GenServer
  def handle_continue(:setup_ets, state) do
    try do
      ets_table = :ets.new(@ets_table_name, [:named_table, :public, read_concurrency: true])
      {:noreply, %{state | ets_table: ets_table}}
    rescue
      ArgumentError ->
        {:stop, {:error, :ets_table_already_exists}, state}
    end
  end

  @impl GenServer
  def handle_call({:embed_state, state}, _from, server_state) do
    with true <- is_map(state),
         true <- Map.has_key?(state, :current_claim),
         true <- Map.has_key?(state, :support_strength),
         true <- Map.has_key?(state, :cycle_count) do
      claim = Map.get(state, :current_claim)
      support = Map.get(state, :support_strength)
      cycle = Map.get(state, :cycle_count)

      cache_key = {:state, claim, support, cycle}

      case :ets.lookup(@ets_table_name, cache_key) do
        [{^cache_key, embedding}] ->
          {:reply, {:ok, embedding}, server_state}

        [] ->
          embedding = compute_state_embedding(state)
          :ets.insert(@ets_table_name, {cache_key, embedding})
          {:reply, {:ok, embedding}, server_state}
      end
    else
      _ ->
        {:reply, {:error, "Invalid state structure"}, server_state}
    end
  end

  @impl GenServer
  def handle_call({:embed_claim, claim_text}, _from, server_state) do
    if is_nil(claim_text) or String.trim(claim_text) == "" do
      {:reply, {:error, "Cannot embed empty string"}, server_state}
    else
      cache_key = {:claim, claim_text}

      case :ets.lookup(@ets_table_name, cache_key) do
        [{^cache_key, embedding}] ->
          {:reply, {:ok, embedding}, server_state}

        [] ->
          embedding = compute_claim_embedding(claim_text)
          :ets.insert(@ets_table_name, {cache_key, embedding})
          {:reply, {:ok, embedding}, server_state}
      end
    end
  end

  @impl GenServer
  def handle_call({:store_trajectory_point, point}, _from, server_state) do
    with blackboard_id when is_integer(blackboard_id) <- Map.get(point, :blackboard_id),
         cycle_number when is_integer(cycle_number) <- Map.get(point, :cycle_number),
         embedding_vector <- Map.get(point, :embedding_vector),
         claim_text <- Map.get(point, :claim_text),
         support_strength when is_number(support_strength) <- Map.get(point, :support_strength) do
      embedding_binary =
        case embedding_vector do
          %Nx.Tensor{} -> :erlang.term_to_binary(embedding_vector)
          _ -> embedding_vector
        end

      attrs = %{
        blackboard_id: blackboard_id,
        cycle_number: cycle_number,
        embedding_vector: embedding_binary,
        claim_text: claim_text,
        support_strength: support_strength
      }

      case TrajectoryPoint.changeset(%TrajectoryPoint{}, attrs) do
        changeset ->
          case Repo.insert(changeset) do
            {:ok, trajectory_point} ->
              {:reply, {:ok, trajectory_point}, server_state}

            {:error, changeset} ->
              {:reply, {:error, changeset}, server_state}
          end
      end
    else
      _ ->
        changeset = TrajectoryPoint.changeset(%TrajectoryPoint{}, %{blackboard_id: nil})
        {:reply, {:error, changeset}, server_state}
    end
  end

  @impl GenServer
  def handle_call({:get_trajectory, blackboard_id}, _from, server_state) do
    query =
      from(t in TrajectoryPoint,
        where: t.blackboard_id == ^blackboard_id,
        order_by: [asc: t.cycle_number]
      )

    trajectory_points = Repo.all(query)

    {:reply, {:ok, trajectory_points}, server_state}
  end

  @doc """
  Handles GenServer termination and cleanup.

  Deletes the ETS table if this process owns it. For normal shutdowns, logs
  an informational message. For crash reasons, logs at warning level with
  full reason details.

  ## Examples

      # Normal shutdown logs:
      # "Shutting down Embedding.Space with reason: :normal"

      # Crash shutdown logs:
      # "Embedding.Space terminating with reason: {:error, :out_of_memory}"

  The try/rescue in this function handles the case where the ETS table
  doesn't exist (:ets.delete/2 raises ArgumentError if the table is not found).
  This is cleanup code, so we want to continue shutdown even if ETS deletion fails.
  """
  @impl GenServer
  @spec terminate(term(), t()) :: :ok
  def terminate(reason, state) do
    if state.ets_table do
      try do
        :ets.delete(@ets_table_name)
      rescue
        ArgumentError -> :ok
      end
    end

    case reason do
      :normal ->
        Logger.info("Shutting down Embedding.Space with reason: :normal")

      :shutdown ->
        Logger.info("Shutting down Embedding.Space with reason: :shutdown")

      {:shutdown, _} = shutdown_reason ->
        Logger.info("Shutting down Embedding.Space with reason: #{inspect(shutdown_reason)}")

      other_reason ->
        Logger.warning("Embedding.Space terminating with reason: #{inspect(other_reason)}")
    end

    :ok
  end

  @spec compute_state_embedding(Server.t()) :: Nx.Tensor.t()
  defp compute_state_embedding(%Server{
         current_claim: claim,
         support_strength: support,
         cycle_count: cycle
       }) do
    claim_embedding = embed_claim_direct(claim)

    support_vector = Nx.tensor([support], type: :f32)
    cycle_vector = Nx.tensor([cycle / 100.0], type: :f32)

    combined =
      Nx.concatenate([Nx.flatten(claim_embedding), support_vector, cycle_vector])

    combined
  end

  @spec compute_claim_embedding(String.t()) :: Nx.Tensor.t()
  defp compute_claim_embedding(claim_text) do
    embed_claim_direct(claim_text)
  end

  @spec embed_claim_direct(String.t()) :: {:ok, Nx.Tensor.t()}
  defp embed_claim_direct(claim_text) when is_binary(claim_text) do
    hash1 = :crypto.hash(:md5, claim_text)
    hash2 = :crypto.hash(:ripemd160, claim_text)
    hash3 = :crypto.hash(:sha, claim_text)
    hash4 = :crypto.hash(:sha224, claim_text)
    hash5 = :crypto.hash(:sha256, claim_text)
    hash6 = :crypto.hash(:sha384, claim_text)
    hash7 = :crypto.hash(:sha512, claim_text)

    bytes1 = for <<b::8 <- hash1>>, do: b / 255.0
    bytes2 = for <<b::8 <- hash2>>, do: b / 255.0
    bytes3 = for <<b::8 <- hash3>>, do: b / 255.0
    bytes4 = for <<b::8 <- hash4>>, do: b / 255.0
    bytes5 = for <<b::8 <- hash5>>, do: b / 255.0
    bytes6 = for <<b::8 <- hash6>>, do: b / 255.0
    bytes7 = for <<b::8 <- hash7>>, do: b / 255.0

    random_bytes = for _i <- 1..540, do: :rand.uniform() * 2.0 - 1.0

    all_bytes = bytes1 ++ bytes2 ++ bytes3 ++ bytes4 ++ bytes5 ++ bytes6 ++ bytes7 ++ random_bytes

    Nx.tensor(all_bytes, type: :f32)
  end
end
