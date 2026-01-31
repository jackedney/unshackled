defmodule Unshackled.Agents.Metadata do
  @moduledoc """
  Centralized agent metadata including colors, display names, and descriptions.

  This module provides a single source of truth for all agent metadata,
  making it easy to add new agents or update existing ones.

  ## Examples

      iex> Metadata.color(:explorer)
      "#22c55e"
      
      iex> Metadata.bg_class(:explorer)
      "bg-[#22c55e]"
      
      iex> Metadata.display_name(:explorer)
      "Explorer"
      
      iex> Metadata.from_string("explorer")
      :explorer
      
      iex> Metadata.from_string("nonexistent")
      nil
  """

  @agents %{
    explorer: %{
      color: "#22c55e",
      display_name: "Explorer",
      description: "Extend claims by one inferential step"
    },
    critic: %{
      color: "#ef4444",
      display_name: "Critic",
      description: "Attack weakest premise of claims"
    },
    connector: %{
      color: "#3b82f6",
      display_name: "Connector",
      description: "Find cross-domain analogies"
    },
    steelman: %{
      color: "#eab308",
      display_name: "Steelman",
      description: "Construct strongest opposing view"
    },
    operationalizer: %{
      color: "#f97316",
      display_name: "Operationalizer",
      description: "Convert claims to falsifiable predictions"
    },
    quantifier: %{
      color: "#8b5cf6",
      display_name: "Quantifier",
      description: "Add numerical precision to claims"
    },
    reducer: %{
      color: "#06b6d4",
      display_name: "Reducer",
      description: "Compress claims to their fundamental essence"
    },
    boundary_hunter: %{
      color: "#ec4899",
      display_name: "Boundary Hunter",
      description: "Find edge cases where claims break"
    },
    translator: %{
      color: "#14b8a6",
      display_name: "Translator",
      description: "Restate claims in different frameworks"
    },
    historian: %{
      color: "#a855f7",
      display_name: "Historian",
      description: "Detect re-treading of previous claims"
    },
    grave_keeper: %{
      color: "#6b7280",
      display_name: "Grave Keeper",
      description: "Track patterns in why ideas die"
    },
    cartographer: %{
      color: "#f59e0b",
      display_name: "Cartographer",
      description: "Navigate embedding space"
    },
    perturber: %{
      color: "#dc2626",
      display_name: "Perturber",
      description: "Inject frontier ideas into debate"
    }
  }

  @doc """
  Returns a list of all agent roles.

  ## Examples

      iex> Metadata.all_roles()
      [:explorer, :critic, :connector, ...]
  """
  @spec all_roles() :: [atom()]
  def all_roles, do: Map.keys(@agents)

  @doc """
  Returns the hex color code for an agent role.

  ## Examples

      iex> Metadata.color(:explorer)
      "#22c55e"
      
      iex> Metadata.color(:nonexistent)
      nil
  """
  @spec color(atom()) :: String.t() | nil
  def color(role) when is_atom(role) do
    get_in(@agents, [role, :color])
  end

  def color(role) when is_binary(role) do
    case from_string(role) do
      nil -> nil
      atom -> color(atom)
    end
  end

  @doc """
  Returns the Tailwind CSS background class for an agent role.

  ## Examples

      iex> Metadata.bg_class(:explorer)
      "bg-[#22c55e]"
      
      iex> Metadata.bg_class(:nonexistent)
      nil
  """
  @spec bg_class(atom()) :: String.t() | nil
  def bg_class(role) when is_atom(role) do
    case color(role) do
      nil -> nil
      hex -> "bg-[#{hex}]"
    end
  end

  def bg_class(role) when is_binary(role) do
    case from_string(role) do
      nil -> nil
      atom -> bg_class(atom)
    end
  end

  @doc """
  Returns the display name for an agent role.

  ## Examples

      iex> Metadata.display_name(:explorer)
      "Explorer"
      
      iex> Metadata.display_name(:boundary_hunter)
      "Boundary Hunter"
      
      iex> Metadata.display_name(:nonexistent)
      nil
  """
  @spec display_name(atom()) :: String.t() | nil
  def display_name(role) when is_atom(role) do
    get_in(@agents, [role, :display_name])
  end

  def display_name(role) when is_binary(role) do
    case from_string(role) do
      nil -> nil
      atom -> display_name(atom)
    end
  end

  @doc """
  Converts a string role to an atom.

  ## Examples

      iex> Metadata.from_string("explorer")
      :explorer
      
      iex> Metadata.from_string("boundary_hunter")
      :boundary_hunter
      
      iex> Metadata.from_string("nonexistent")
      nil
  """
  @spec from_string(String.t()) :: atom() | nil
  def from_string(role_string) when is_binary(role_string) do
    case Map.has_key?(@agents, String.to_existing_atom(role_string)) do
      true -> String.to_existing_atom(role_string)
      false -> nil
    end
  rescue
    ArgumentError -> nil
  end
end
