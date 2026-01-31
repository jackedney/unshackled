defmodule UnshackledWeb.Router do
  use UnshackledWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {UnshackledWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", UnshackledWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/sessions", SessionsLive.Index, :index)
    live("/sessions/new", SessionsLive.New, :new)
    live("/sessions/:id", SessionsLive.Show, :show)
  end
end
