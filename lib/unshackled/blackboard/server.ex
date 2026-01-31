defmodule Unshackled.Blackboard.Server do
  @moduledoc """
  GenServer managing of Blackboard state for Unshackled system.
  Provides atomic read/write access to shared state for all agents.
  """

  use GenServer
  import Ecto.Query
  require Logger

  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Blackboard.BlackboardSnapshot
  alias Unshackled.Blackboard.CemeteryEntry
  alias Unshackled.Blackboard.FrontierIdea
  alias Unshackled.GenServer.TerminateHelper
  alias Unshackled.Repo

  defstruct [
    :current_claim,
    :support_strength,
    :active_objection,
    :analogy_of_record,
    :frontier_pool,
    :cemetery,
    :graduated_claims,
    :cycle_count,
    :blackboard_id,
    :blackboard_name,
    :embedding,
    :translator_frameworks_used,
    :cost_limit_usd
  ]

  @type t :: %__MODULE__{
          current_claim: String.t(),
          support_strength: float(),
          active_objection: String.t() | nil,
          analogy_of_record: String.t() | nil,
          frontier_pool: map() | nil,
          cemetery: list(map()),
          graduated_claims: list(map()),
          cycle_count: non_neg_integer(),
          blackboard_id: pos_integer() | nil,
          blackboard_name: atom() | nil,
          embedding: binary() | nil,
          translator_frameworks_used: list(String.t()),
          cost_limit_usd: float() | nil
        }

  @type frontier_idea :: %{
          id: String.t(),
          idea_text: String.t(),
          sponsor_ids: [String.t()],
          sponsor_count: non_neg_integer(),
          cycles_alive: non_neg_integer(),
          activated: boolean()
        }

  @type cemetery_entry :: %{
          claim: String.t(),
          cause_of_death: String.t(),
          final_support: float(),
          cycle_killed: non_neg_integer()
        }

  @type graduated_claim :: %{
          claim: String.t(),
          final_support: float(),
          cycle_graduated: non_neg_integer()
        }

  @support_floor 0.2
  @support_ceiling 0.9
  @graduation_threshold 0.85

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(seed_claim) when is_binary(seed_claim) do
    GenServer.start_link(__MODULE__, seed_claim, name: __MODULE__)
  end

  @spec start_link(String.t(), atom()) :: GenServer.on_start()
  def start_link(seed_claim, name) when is_binary(seed_claim) and is_atom(name) do
    GenServer.start_link(__MODULE__, seed_claim, name: name)
  end

  @spec start_link(String.t(), atom(), keyword()) :: GenServer.on_start()
  def start_link(seed_claim, name, opts) when is_binary(seed_claim) and is_atom(name) do
    GenServer.start_link(__MODULE__, {seed_claim, opts}, name: name)
  end

  @impl GenServer
  def init(seed_claim) when is_binary(seed_claim) do
    {:ok, default_state(seed_claim)}
  end

  @impl GenServer
  def init({seed_claim, opts}) when is_binary(seed_claim) and is_list(opts) do
    {:ok, default_state(seed_claim, opts)}
  end

  @spec default_state(String.t(), keyword()) :: t()
  defp default_state(seed_claim, opts \\ []) do
    %__MODULE__{
      current_claim: seed_claim,
      support_strength: 0.5,
      active_objection: nil,
      analogy_of_record: nil,
      frontier_pool: %{},
      cemetery: [],
      graduated_claims: [],
      cycle_count: 0,
      blackboard_id: nil,
      blackboard_name: nil,
      embedding: nil,
      translator_frameworks_used: [],
      cost_limit_usd: Keyword.get(opts, :cost_limit_usd)
    }
  end

  @spec get_state(atom()) :: t()
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  @spec update_claim(atom(), String.t()) :: :ok
  def update_claim(server \\ __MODULE__, new_claim) when is_binary(new_claim) do
    GenServer.call(server, {:update_claim, new_claim})
  end

  @spec update_support(atom(), float()) :: :ok
  def update_support(server \\ __MODULE__, delta) when is_number(delta) do
    GenServer.call(server, {:update_support, delta})
  end

  @spec set_active_objection(atom(), String.t() | nil) :: :ok
  def set_active_objection(server \\ __MODULE__, objection)
      when is_binary(objection) or is_nil(objection) do
    GenServer.cast(server, {:set_active_objection, objection})
  end

  @spec set_analogy(atom(), String.t() | nil) :: :ok
  def set_analogy(server \\ __MODULE__, analogy)
      when is_binary(analogy) or is_nil(analogy) do
    GenServer.cast(server, {:set_analogy, analogy})
  end

  @spec increment_cycle(atom()) :: :ok
  def increment_cycle(server \\ __MODULE__) do
    GenServer.call(server, :increment_cycle)
  end

  @spec get_cemetery(atom()) :: list(map())
  def get_cemetery(server \\ __MODULE__) do
    GenServer.call(server, :get_cemetery)
  end

  @spec get_graduated(atom()) :: list(map())
  def get_graduated(server \\ __MODULE__) do
    GenServer.call(server, :get_graduated)
  end

  @spec kill_claim(atom(), String.t()) :: :ok
  def kill_claim(server \\ __MODULE__, cause_of_death) when is_binary(cause_of_death) do
    GenServer.call(server, {:kill_claim, cause_of_death})
  end

  @spec set_blackboard_id(atom(), pos_integer()) :: :ok
  def set_blackboard_id(server \\ __MODULE__, blackboard_id)
      when is_integer(blackboard_id) and blackboard_id > 0 do
    GenServer.call(server, {:set_blackboard_id, blackboard_id})
  end

  @spec add_frontier_idea(atom(), String.t(), String.t() | integer()) :: :ok
  def add_frontier_idea(server \\ __MODULE__, idea_text, sponsor_id) when is_binary(idea_text) do
    GenServer.call(server, {:add_frontier_idea, idea_text, sponsor_id})
  end

  @spec get_eligible_frontiers(atom()) :: list(map())
  def get_eligible_frontiers(server \\ __MODULE__) do
    GenServer.call(server, :get_eligible_frontiers)
  end

  @spec activate_frontier(atom(), String.t()) :: :ok | {:error, String.t()}
  def activate_frontier(server \\ __MODULE__, idea_id) when is_binary(idea_id) do
    GenServer.call(server, {:activate_frontier, idea_id})
  end

  @spec age_frontiers(atom()) :: :ok
  def age_frontiers(server \\ __MODULE__) do
    GenServer.call(server, :age_frontiers)
  end

  @spec select_weighted_frontier(atom()) :: map() | nil
  def select_weighted_frontier(server \\ __MODULE__) do
    GenServer.call(server, :select_weighted_frontier)
  end

  @spec get_next_translator_framework(atom()) :: String.t()
  def get_next_translator_framework(server \\ __MODULE__) do
    GenServer.call(server, :get_next_translator_framework)
  end

  @spec record_translator_framework(atom(), String.t()) :: :ok
  def record_translator_framework(server \\ __MODULE__, framework) when is_binary(framework) do
    GenServer.call(server, {:record_translator_framework, framework})
  end

  @spec persist_state(atom()) :: {:ok, pos_integer()} | {:error, term()}
  def persist_state(server \\ __MODULE__) do
    GenServer.call(server, :persist_state)
  end

  @spec create_snapshot(atom()) :: {:ok, pos_integer()} | {:error, term()}
  def create_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :create_snapshot)
  end

  @spec load_state(atom(), pos_integer()) :: :ok | {:error, String.t()}
  def load_state(server \\ __MODULE__, blackboard_id)
      when is_integer(blackboard_id) and blackboard_id > 0 do
    GenServer.call(server, {:load_state, blackboard_id})
  end

  @spec get_snapshots(atom(), non_neg_integer(), non_neg_integer()) ::
          list(map()) | {:error, String.t()}
  def get_snapshots(server \\ __MODULE__, from_cycle, to_cycle)
      when is_integer(from_cycle) and is_integer(to_cycle) and
             from_cycle >= 0 and to_cycle >= 0 do
    GenServer.call(server, {:get_snapshots, from_cycle, to_cycle})
  end

  # GenServer callbacks
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    case Process.info(self(), :registered_name) do
      {:registered_name, name} when is_atom(name) ->
        state_with_name = Map.put(state, :blackboard_name, name)
        {:reply, state_with_name, state}

      _ ->
        {:reply, state, state}
    end
  end

  @impl GenServer
  def handle_call({:update_claim, new_claim}, _from, state) do
    new_state = %{state | current_claim: new_claim}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:update_support, delta}, _from, state) do
    old_support = state.support_strength
    unclamped_support = old_support + delta

    {new_support, should_graduate, reason} =
      cond do
        unclamped_support >= @graduation_threshold ->
          {@graduation_threshold, true, "Confidence reached graduation threshold (0.85)"}

        unclamped_support <= @support_floor ->
          {@support_floor, false, "Support decayed to floor (0.2)"}

        unclamped_support >= @support_ceiling ->
          {@support_ceiling, false, "Support clamped at ceiling (0.9)"}

        true ->
          {unclamped_support, false, "Agent contribution delta applied"}
      end

    if new_support != old_support do
      Logger.info(
        metadata: [cycle_number: state.cycle_count],
        message:
          "Confidence updated: #{Float.round(old_support, 4)} -> #{Float.round(new_support, 4)} (reason: #{reason})"
      )
    end

    new_state = %{state | support_strength: new_support}

    new_state =
      if new_support == @support_floor do
        kill_claim_internal(new_state, "Support decay below threshold")
      else
        new_state
      end

    new_state =
      if should_graduate do
        graduate_claim_internal(new_state)
      else
        new_state
      end

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:increment_cycle, _from, state) do
    new_state = %{state | cycle_count: state.cycle_count + 1}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_cemetery, _from, state) do
    {:reply, state.cemetery, state}
  end

  @impl GenServer
  def handle_call(:get_graduated, _from, state) do
    {:reply, state.graduated_claims, state}
  end

  @impl GenServer
  def handle_call({:kill_claim, cause_of_death}, _from, state) do
    new_state = kill_claim_internal(state, cause_of_death)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:set_blackboard_id, blackboard_id}, _from, state) do
    new_state = %{state | blackboard_id: blackboard_id}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_eligible_frontiers, _from, state) do
    eligible =
      state.frontier_pool
      |> Enum.filter(fn {_id, idea} ->
        sponsor_count = Map.get(idea, :sponsor_count) || Map.get(idea, "sponsor_count") || 0
        activated = Map.get(idea, :activated) || Map.get(idea, "activated") || false
        sponsor_count >= 2 and not activated
      end)
      |> Enum.map(fn {id, idea} -> Map.put(idea, :id, id) end)

    {:reply, eligible, state}
  end

  @impl GenServer
  def handle_call({:activate_frontier, idea_id}, _from, state) do
    case Map.get(state.frontier_pool, idea_id) do
      nil ->
        {:reply, {:error, "Idea not found"}, state}

      %{activated: true} ->
        {:reply, {:error, "Idea already activated"}, state}

      idea ->
        new_pool = Map.put(state.frontier_pool, idea_id, %{idea | activated: true})
        new_state = %{state | frontier_pool: new_pool}
        persist_frontier(state, idea, :activate)
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(:select_weighted_frontier, _from, state) do
    selected = select_frontier_by_weight(state.frontier_pool)
    {:reply, selected, state}
  end

  @impl GenServer
  def handle_call({:add_frontier_idea, idea_text, sponsor_id}, _from, state) do
    new_pool = add_idea_to_pool(state.frontier_pool, idea_text, sponsor_id, state)
    new_state = %{state | frontier_pool: new_pool}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:age_frontiers, _from, state) do
    new_pool = age_frontier_pool(state.frontier_pool, state)
    new_state = %{state | frontier_pool: new_pool}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_next_translator_framework, _from, state) do
    frameworks = ~w(physics information_theory economics biology mathematics)

    next_framework =
      case frameworks -- (state.translator_frameworks_used || []) do
        [first | _rest] -> first
        [] -> hd(frameworks)
      end

    {:reply, next_framework, state}
  end

  @impl GenServer
  def handle_call({:record_translator_framework, framework}, _from, state) do
    new_frameworks_used = [framework | state.translator_frameworks_used || []] |> Enum.uniq()
    new_state = %{state | translator_frameworks_used: new_frameworks_used}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:set_embedding, embedding}, _from, state) do
    {:reply, {:ok, %{state | embedding: embedding}}, %{state | embedding: embedding}}
  end

  @impl GenServer
  def handle_call(:persist_state, _from, state) do
    cemetery_map =
      state.cemetery
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} -> {index, entry} end)
      |> Map.new()

    attrs = %{
      current_claim: state.current_claim,
      support_strength: state.support_strength,
      active_objection: state.active_objection,
      analogy_of_record: state.analogy_of_record,
      frontier_pool: state.frontier_pool,
      cemetery: cemetery_map,
      cycle_count: state.cycle_count,
      embedding: state.embedding,
      translator_frameworks_used: state.translator_frameworks_used || [],
      cost_limit_usd: state.cost_limit_usd
    }

    case state.blackboard_id do
      nil ->
        changeset = BlackboardRecord.changeset(%BlackboardRecord{}, attrs)

        case Repo.insert(changeset) do
          {:ok, record} ->
            new_state = %{state | blackboard_id: record.id}
            {:reply, {:ok, record.id}, new_state}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state}
        end

      id ->
        existing = Repo.get(BlackboardRecord, id)

        if existing do
          changeset = BlackboardRecord.changeset(existing, attrs)

          case Repo.update(changeset) do
            {:ok, _record} ->
              {:reply, {:ok, id}, state}

            {:error, changeset} ->
              {:reply, {:error, changeset}, state}
          end
        else
          changeset = BlackboardRecord.changeset(%BlackboardRecord{}, attrs)

          case Repo.insert(changeset) do
            {:ok, record} ->
              new_state = %{state | blackboard_id: record.id}
              {:reply, {:ok, record.id}, new_state}

            {:error, changeset} ->
              {:reply, {:error, changeset}, state}
          end
        end
    end
  end

  @impl GenServer
  def handle_call(:create_snapshot, _from, state) do
    if state.blackboard_id == nil do
      {:reply, {:error, "No blackboard_id set. Call persist_state first."}, state}
    else
      state_json = %{
        current_claim: state.current_claim,
        support_strength: state.support_strength,
        active_objection: state.active_objection,
        analogy_of_record: state.analogy_of_record,
        frontier_pool: state.frontier_pool,
        cemetery: state.cemetery,
        graduated_claims: state.graduated_claims,
        cycle_count: state.cycle_count
      }

      attrs = %{
        blackboard_id: state.blackboard_id,
        cycle_number: state.cycle_count,
        state_json: state_json,
        embedding_vector: state.embedding
      }

      changeset = BlackboardSnapshot.changeset(%BlackboardSnapshot{}, attrs)

      case Repo.insert(changeset) do
        {:ok, snapshot} ->
          {:reply, {:ok, snapshot.id}, state}

        {:error, changeset} ->
          {:reply, {:error, changeset}, state}
      end
    end
  end

  @impl GenServer
  def handle_call({:load_state, blackboard_id}, _from, state) do
    case Repo.get(BlackboardRecord, blackboard_id) do
      nil ->
        {:reply, {:error, "Blackboard not found with id: #{blackboard_id}"}, state}

      record ->
        new_state = %{
          state
          | current_claim: record.current_claim,
            support_strength: record.support_strength,
            active_objection: record.active_objection,
            analogy_of_record: record.analogy_of_record,
            frontier_pool: record.frontier_pool || %{},
            cemetery: record.cemetery || [],
            graduated_claims: [],
            cycle_count: record.cycle_count,
            blackboard_id: record.id,
            embedding: record.embedding,
            translator_frameworks_used: record.translator_frameworks_used || []
        }

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:get_snapshots, from_cycle, to_cycle}, _from, state) do
    if state.blackboard_id == nil do
      {:reply, {:error, "No blackboard_id set"}, state}
    else
      snapshots =
        from(s in BlackboardSnapshot,
          where: s.blackboard_id == ^state.blackboard_id,
          where: s.cycle_number >= ^from_cycle and s.cycle_number <= ^to_cycle,
          order_by: [asc: s.cycle_number]
        )
        |> Repo.all()

      snapshot_maps =
        Enum.map(snapshots, fn snapshot ->
          %{
            id: snapshot.id,
            blackboard_id: snapshot.blackboard_id,
            cycle_number: snapshot.cycle_number,
            state_json: snapshot.state_json,
            embedding_vector: snapshot.embedding_vector,
            inserted_at: snapshot.inserted_at
          }
        end)

      {:reply, snapshot_maps, state}
    end
  end

  @impl GenServer
  def handle_cast({:set_active_objection, objection}, state) do
    {:noreply, %{state | active_objection: objection}}
  end

  @impl GenServer
  def handle_cast({:set_analogy, analogy}, state) do
    {:noreply, %{state | analogy_of_record: analogy}}
  end

  @doc """
  Handles GenServer termination and cleanup.

  Logs the shutdown reason and optionally persists the final state to the database.
  For normal shutdowns, a brief log message is emitted. For crash reasons, the
  full reason is logged at warning level for debugging purposes.
  """
  @impl GenServer
  @spec terminate(term(), t()) :: :ok
  def terminate(reason, state) do
    TerminateHelper.log_shutdown("Blackboard.Server", reason, state.cycle_count)
  end

  @spec kill_claim_internal(t(), String.t()) :: t()
  defp kill_claim_internal(state, cause_of_death) do
    if state.current_claim == nil do
      state
    else
      Logger.warning(
        metadata: [cycle_number: state.cycle_count],
        message:
          "Claim died at cycle #{state.cycle_count} - cause: #{cause_of_death}, final support: #{Float.round(state.support_strength, 4)}"
      )

      Logger.info(
        metadata: [cycle_number: state.cycle_count],
        message: "Claim: #{String.slice(state.current_claim, 0, 80)}..."
      )

      cemetery_entry = %{
        claim: state.current_claim,
        cause_of_death: cause_of_death,
        final_support: state.support_strength,
        cycle_killed: state.cycle_count
      }

      new_cemetery = [cemetery_entry | state.cemetery]

      persist_cemetery_entry(state, cemetery_entry)

      %{state | cemetery: new_cemetery, current_claim: nil}
    end
  end

  @spec graduate_claim_internal(t()) :: t()
  defp graduate_claim_internal(state) do
    if state.current_claim == nil do
      state
    else
      Logger.info(
        metadata: [cycle_number: state.cycle_count],
        message:
          "Claim graduated at cycle #{state.cycle_count} - final support: #{Float.round(state.support_strength, 4)}"
      )

      Logger.info(
        metadata: [cycle_number: state.cycle_count],
        message: "Claim: #{String.slice(state.current_claim, 0, 80)}..."
      )

      graduated_entry = %{
        claim: state.current_claim,
        final_support: state.support_strength,
        cycle_graduated: state.cycle_count
      }

      new_graduated = [graduated_entry | state.graduated_claims]

      %{state | graduated_claims: new_graduated, current_claim: nil}
    end
  end

  @spec persist_cemetery_entry(t(), cemetery_entry()) :: :ok | {:error, Ecto.Changeset.t()}
  defp persist_cemetery_entry(state, entry) do
    if state.blackboard_id do
      changeset =
        CemeteryEntry.changeset(
          %CemeteryEntry{},
          Map.put(entry, :blackboard_id, state.blackboard_id)
        )

      case Repo.insert(changeset) do
        {:ok, _} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      :ok
    end
  end

  @spec add_idea_to_pool(map(), String.t(), String.t() | integer(), t()) :: map()
  defp add_idea_to_pool(pool, idea_text, sponsor_id, state) do
    idea_key = :crypto.hash(:sha256, idea_text) |> Base.encode16()

    case Map.get(pool, idea_key) do
      nil ->
        new_idea = %{
          id: idea_key,
          idea_text: idea_text,
          sponsor_ids: [sponsor_id],
          sponsor_count: 1,
          cycles_alive: 0,
          activated: false
        }

        persist_frontier(state, new_idea, :create)
        Map.put(pool, idea_key, new_idea)

      idea ->
        if sponsor_id in idea.sponsor_ids do
          pool
        else
          updated_idea = %{
            idea
            | sponsor_ids: [sponsor_id | idea.sponsor_ids],
              sponsor_count: idea.sponsor_count + 1
          }

          persist_frontier(state, updated_idea, :update)
          Map.put(pool, idea_key, updated_idea)
        end
    end
  end

  @spec age_frontier_pool(map(), t()) :: map()
  defp age_frontier_pool(pool, state) do
    Enum.reduce(pool, %{}, fn {id, idea}, acc ->
      new_cycles_alive = idea.cycles_alive + 1

      if new_cycles_alive > 10 do
        persist_frontier(state, idea, :delete)
        acc
      else
        updated_idea = %{idea | cycles_alive: new_cycles_alive}
        persist_frontier(state, updated_idea, :update)
        Map.put(acc, id, updated_idea)
      end
    end)
  end

  @spec persist_frontier(t(), frontier_idea(), :create | :update | :activate | :delete) :: :ok
  defp persist_frontier(%{blackboard_id: nil}, _idea, _action), do: :ok

  defp persist_frontier(state, idea, :create) do
    changeset =
      FrontierIdea.changeset(%FrontierIdea{}, %{
        blackboard_id: state.blackboard_id,
        idea_text: idea.idea_text,
        sponsor_count: idea.sponsor_count,
        cycles_alive: idea.cycles_alive,
        activated: idea.activated
      })

    case Repo.insert(changeset) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp persist_frontier(state, idea, :update) do
    with_existing_frontier(state, idea, fn existing ->
      changeset =
        FrontierIdea.changeset(existing, %{
          sponsor_count: idea.sponsor_count,
          cycles_alive: idea.cycles_alive,
          activated: idea.activated
        })

      Repo.update(changeset)
    end)
  end

  defp persist_frontier(state, idea, :activate) do
    with_existing_frontier(state, idea, fn existing ->
      changeset = FrontierIdea.changeset(existing, %{activated: true})
      Repo.update(changeset)
    end)
  end

  defp persist_frontier(state, idea, :delete) do
    with_existing_frontier(state, idea, fn existing ->
      Repo.delete(existing)
    end)
  end

  @spec with_existing_frontier(t(), frontier_idea(), (FrontierIdea.t() -> term())) :: :ok
  defp with_existing_frontier(state, idea, fun) do
    case Repo.get_by(FrontierIdea, idea_text: idea.idea_text, blackboard_id: state.blackboard_id) do
      nil -> :ok
      existing -> fun.(existing)
    end

    :ok
  end

  @spec select_frontier_by_weight(map()) :: map() | nil
  defp select_frontier_by_weight(pool) do
    eligible =
      pool
      |> Enum.filter(fn {_id, idea} -> idea.sponsor_count >= 2 and not idea.activated end)
      |> Enum.map(fn {id, idea} ->
        weight = calculate_weight(idea.sponsor_count, idea.cycles_alive)
        {id, Map.put(idea, :id, id), weight}
      end)

    case eligible do
      [] ->
        nil

      ideas ->
        total_weight = Enum.reduce(ideas, 0, fn {_id, _idea, weight}, acc -> acc + weight end)
        random = :rand.uniform() * total_weight

        select_by_weight(ideas, random, 0)
    end
  end

  @spec calculate_weight(non_neg_integer(), non_neg_integer()) :: float()
  defp calculate_weight(sponsor_count, cycles_alive) when cycles_alive > 0 do
    sponsor_count / cycles_alive
  end

  defp calculate_weight(sponsor_count, 0), do: sponsor_count * 1.0

  @spec select_by_weight([{String.t(), map(), float()}], float(), float()) :: map() | nil
  defp select_by_weight([], _random, _accumulated), do: nil

  defp select_by_weight([{id, idea, weight} | rest], random, accumulated) do
    if random <= accumulated + weight do
      Map.put(idea, :id, id)
    else
      select_by_weight(rest, random, accumulated + weight)
    end
  end
end
