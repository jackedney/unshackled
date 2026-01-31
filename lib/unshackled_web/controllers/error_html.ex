defmodule UnshackledWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.
  """

  use UnshackledWeb, :html

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
