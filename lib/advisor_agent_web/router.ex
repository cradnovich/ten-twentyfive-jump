defmodule AdvisorAgentWeb.Router do
  use AdvisorAgentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AdvisorAgentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug AdvisorAgentWeb.Plugs.SetCurrentUser
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AdvisorAgentWeb do
    pipe_through :browser

    live "/", ChatLive, :index
    live "/settings", SettingsLive, :index
  end

  scope "/auth", AdvisorAgentWeb do
    pipe_through :browser

    get "/logout", AuthController, :delete
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Other scopes may use custom stacks.
  # scope "/api", AdvisorAgentWeb do
  #   pipe_through :api
  # end
end
