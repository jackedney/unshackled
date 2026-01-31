defmodule UnshackledWeb.PubSubTest do
  use ExUnit.Case, async: true

  alias UnshackledWeb.PubSub

  describe "topic helpers" do
    test "session_topic/1 returns correct topic" do
      assert PubSub.session_topic("session_1") == "session:session_1"
      assert PubSub.session_topic("session_42") == "session:session_42"
    end

    test "sessions_topic/0 returns correct topic" do
      assert PubSub.sessions_topic() == "sessions"
    end
  end

  describe "subscriptions" do
    test "subscribe_session/1 subscribes to session topic" do
      session_id = "test_session_#{System.unique_integer()}"
      assert :ok = PubSub.subscribe_session(session_id)

      # Verify we receive messages on this topic
      PubSub.broadcast_session_paused(session_id)
      assert_receive {:session_paused, ^session_id}
    end

    test "subscribe_sessions/0 subscribes to sessions topic" do
      assert :ok = PubSub.subscribe_sessions()

      session_id = "test_session_#{System.unique_integer()}"
      PubSub.broadcast_session_started(session_id, 123)
      assert_receive {:session_started, ^session_id, 123}
    end

    test "unsubscribe_session/1 stops receiving messages" do
      session_id = "test_session_#{System.unique_integer()}"
      :ok = PubSub.subscribe_session(session_id)
      :ok = PubSub.unsubscribe_session(session_id)

      PubSub.broadcast_session_paused(session_id)
      refute_receive {:session_paused, ^session_id}, 100
    end
  end

  describe "session lifecycle broadcasts" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      :ok = PubSub.subscribe_session(session_id)
      :ok = PubSub.subscribe_sessions()
      {:ok, session_id: session_id}
    end

    test "broadcast_session_started/2 sends to both topics", %{session_id: session_id} do
      PubSub.broadcast_session_started(session_id, 42)

      # Should receive on both session and sessions topics
      assert_receive {:session_started, ^session_id, 42}
      assert_receive {:session_started, ^session_id, 42}
    end

    test "broadcast_session_paused/1 sends to both topics", %{session_id: session_id} do
      PubSub.broadcast_session_paused(session_id)

      assert_receive {:session_paused, ^session_id}
      assert_receive {:session_paused, ^session_id}
    end

    test "broadcast_session_resumed/1 sends to both topics", %{session_id: session_id} do
      PubSub.broadcast_session_resumed(session_id)

      assert_receive {:session_resumed, ^session_id}
      assert_receive {:session_resumed, ^session_id}
    end

    test "broadcast_session_stopped/1 sends to both topics", %{session_id: session_id} do
      PubSub.broadcast_session_stopped(session_id)

      assert_receive {:session_stopped, ^session_id}
      assert_receive {:session_stopped, ^session_id}
    end

    test "broadcast_session_completed/1 sends to both topics", %{session_id: session_id} do
      PubSub.broadcast_session_completed(session_id)

      assert_receive {:session_completed, ^session_id}
      assert_receive {:session_completed, ^session_id}
    end
  end

  describe "cycle broadcasts" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      :ok = PubSub.subscribe_session(session_id)
      {:ok, session_id: session_id}
    end

    test "broadcast_cycle_started/2 sends cycle data", %{session_id: session_id} do
      cycle_data = %{
        session_id: session_id,
        cycle_number: 5,
        blackboard_id: 123
      }

      PubSub.broadcast_cycle_started(session_id, cycle_data)

      assert_receive {:cycle_started, ^cycle_data}
    end

    test "broadcast_cycle_complete/2 sends cycle data", %{session_id: session_id} do
      cycle_data = %{
        session_id: session_id,
        cycle_number: 5,
        blackboard_id: 123,
        duration_ms: 150,
        support_strength: 0.75,
        current_claim: "Test claim"
      }

      PubSub.broadcast_cycle_complete(session_id, cycle_data)

      assert_receive {:cycle_complete, ^cycle_data}
    end
  end

  describe "blackboard state broadcasts" do
    setup do
      session_id = "test_session_#{System.unique_integer()}"
      :ok = PubSub.subscribe_session(session_id)
      {:ok, session_id: session_id}
    end

    test "broadcast_blackboard_updated/2 sends state", %{session_id: session_id} do
      state = %{current_claim: "claim", support_strength: 0.5}

      PubSub.broadcast_blackboard_updated(session_id, state)

      assert_receive {:blackboard_updated, ^state}
    end

    test "broadcast_claim_updated/2 sends new claim", %{session_id: session_id} do
      PubSub.broadcast_claim_updated(session_id, "new claim")

      assert_receive {:claim_updated, "new claim"}
    end

    test "broadcast_support_updated/2 sends new support", %{session_id: session_id} do
      PubSub.broadcast_support_updated(session_id, 0.85)

      assert_receive {:support_updated, 0.85}
    end

    test "broadcast_claim_died/2 sends cemetery entry", %{session_id: session_id} do
      entry = %{claim: "dead claim", cause_of_death: "decay", cycle_killed: 10}

      PubSub.broadcast_claim_died(session_id, entry)

      assert_receive {:claim_died, ^entry}
    end

    test "broadcast_claim_graduated/2 sends graduated entry", %{session_id: session_id} do
      entry = %{claim: "graduated claim", final_support: 0.85, cycle_graduated: 20}

      PubSub.broadcast_claim_graduated(session_id, entry)

      assert_receive {:claim_graduated, ^entry}
    end
  end
end
