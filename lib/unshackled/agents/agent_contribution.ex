defmodule Unshackled.Agents.AgentContribution do
  @moduledoc """
  Ecto schema for the agent_contributions table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_agent_roles ~w[
    explorer
    critic
    connector
    steelman
    operationalizer
    quantifier
    reducer
    boundary_hunter
    translator
    historian
    grave_keeper
    cartographer
    perturber
  ]

  @type t :: %__MODULE__{
          cycle_number: integer() | nil,
          agent_role: String.t(),
          model_used: String.t(),
          input_prompt: String.t() | nil,
          output_text: String.t() | nil,
          accepted: boolean(),
          support_delta: float() | nil,
          id: pos_integer() | nil,
          blackboard_id: pos_integer() | nil,
          blackboard: term() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "agent_contributions" do
    field :cycle_number, :integer
    field :agent_role, :string
    field :model_used, :string
    field :input_prompt, :string
    field :output_text, :string
    field :accepted, :boolean
    field :support_delta, :float

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(agent_contribution, attrs) do
    agent_contribution
    |> cast(attrs, [
      :blackboard_id,
      :cycle_number,
      :agent_role,
      :model_used,
      :input_prompt,
      :output_text,
      :accepted,
      :support_delta
    ])
    |> validate_required([
      :blackboard_id,
      :cycle_number,
      :agent_role,
      :model_used,
      :input_prompt,
      :output_text,
      :accepted
    ])
    |> validate_inclusion(:agent_role, @valid_agent_roles,
      message: "must be one of: #{Enum.join(@valid_agent_roles, ", ")}"
    )
  end
end
