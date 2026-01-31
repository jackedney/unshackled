defmodule Unshackled.ConfigHelpers do
  @moduledoc """
  Macros to reduce boilerplate in configuration modules.

  This module provides the `defconfig/2` macro for generating configuration
  getter functions that read from application environment with fallback to defaults.

  ## Example

      defmodule MyConfig do
        import Unshackled.ConfigHelpers

        defconfig :my_setting, app_key: :my_app, default: "default_value"
      end

  This generates:

      def my_setting do
        Keyword.get(
          Application.get_env(:my_app, :my_settings, []),
          :my_setting,
          "default_value"
        )
      end

  """

  @doc """
  Defines a configuration getter function.

  The generated function reads from the application environment and falls back
  to the specified default value if the configuration is not set.

  ## Options

    * `:app_key` (required) - The application environment key to read from.
      For example, for `Application.get_env(:unshackled, :evolution)`, use `app_key: :evolution`.

    * `:default` (required) - The default value to return if the configuration is not set.

  ## Examples

      defconfig :similarity_threshold, app_key: :evolution, default: 0.85

      defconfig :max_retries, app_key: :api, default: 3

  """
  defmacro defconfig(name, opts) when is_atom(name) and is_list(opts) do
    app_key = Keyword.fetch!(opts, :app_key)
    default = Keyword.fetch!(opts, :default)

    quote do
      @doc """
      Returns the configured #{unquote(name)} value.

      Reads from the application environment or returns the default value.

      ## Examples

          iex> #{__MODULE__}.#{unquote(name)}()
          #{inspect(unquote(default))}

      """
      @spec unquote(name)() :: term()
      def unquote(name)() do
        Keyword.get(
          Application.get_env(:unshackled, unquote(app_key), []),
          unquote(name),
          unquote(Macro.escape(default))
        )
      end
    end
  end
end
