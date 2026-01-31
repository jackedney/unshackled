defmodule BlackboardServerFixtures do
  @moduledoc """
  Test fixtures for Unshackled.Blackboard.Server.
  """

  alias Unshackled.Blackboard.Server

  @doc """
  Creates a test blackboard server with the given claim.
  """
  def blackboard_server(claim \\ "Test claim") do
    {:ok, pid} = Server.start_link(claim, name: :test_blackboard)
    pid
  end

  @doc """
  Returns a test blackboard state map.
  """
  def blackboard_state(claim \\ "Test claim") do
    %Server{
      current_claim: claim,
      support_strength: 0.5,
      active_objection: nil,
      analogy_of_record: nil,
      frontier_pool: %{},
      cemetery: [],
      graduated_claims: [],
      cycle_count: 0,
      blackboard_id: nil,
      embedding: nil,
      translator_frameworks_used: []
    }
  end
end
