defmodule UnshackledWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use UnshackledWeb, :controller` and
  `use UnshackledWeb, :live_view`.

  Note: This module intentionally avoids `use UnshackledWeb, :html` to break
  the compile-time cycle between Layouts -> Router -> Endpoint -> Layouts.
  """
  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import UnshackledWeb.CoreComponents

  embed_templates("layouts/*")

  @doc """
  Determines if a navigation link should be marked as active.

  Returns true if the current path matches or is a child of the given path.
  """
  @spec nav_link_active?(String.t() | nil, String.t()) :: boolean()
  def nav_link_active?(current_path, link_path) do
    current_path && String.starts_with?(current_path, link_path)
  end
end
