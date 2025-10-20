defmodule AdvisorAgentWeb.SettingsLive do
  use AdvisorAgentWeb, :live_view

  alias AdvisorAgent.{OpenAIModels, Repo, User}
  require Logger

  def mount(_params, session, socket) do
    # Load user from session
    current_user =
      case session["user_id"] do
        nil -> nil
        user_id -> Repo.get(User, user_id)
      end

    if current_user do
      {:ok,
       socket
       |> assign(:current_user, current_user)
       |> assign(:openai_api_key, current_user.openai_api_key || "")
       |> assign(:selected_model, current_user.selected_model || Atom.to_string(OpenAIModels.default_chat_model()))
       |> assign(:show_api_key_input, requires_api_key?(current_user.selected_model || Atom.to_string(OpenAIModels.default_chat_model())))}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_event("update_model", %{"model" => model}, socket) do
    {:noreply,
     socket
     |> assign(:selected_model, model)
     |> assign(:show_api_key_input, requires_api_key?(model))}
  end

  def handle_event("update_api_key", %{"api_key" => api_key}, socket) do
    {:noreply, assign(socket, :openai_api_key, api_key)}
  end

  def handle_event("save_settings", _params, socket) do
    current_user = socket.assigns.current_user

    changeset = User.update_ai_settings(current_user, %{
      openai_api_key: socket.assigns.openai_api_key,
      selected_model: socket.assigns.selected_model
    })

    case Repo.update(changeset) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> put_flash(:info, "Settings saved successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  def handle_event("disconnect_hubspot", _params, socket) do
    current_user = socket.assigns.current_user

    changeset = User.clear_hubspot_credentials(current_user)

    case Repo.update(changeset) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> put_flash(:info, "Hubspot disconnected successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to disconnect Hubspot")}
    end
  end

  # Helper function to determine if a model requires an API key
  # For now, we'll say that all models except for a specific "self-hosted" model require an API key
  # In the future, this can be expanded to include other self-hosted models
  defp requires_api_key?("self-hosted"), do: false
  defp requires_api_key?(_model), do: true

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-4xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
        <!-- Header -->
        <div class="mb-8">
          <.link navigate="/" class="text-blue-600 hover:text-blue-800 flex items-center mb-4">
            <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
            </svg>
            Back to Chat
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">Settings</h1>
        </div>

        <!-- Hubspot Connection Section -->
        <div class="bg-white shadow rounded-lg mb-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">Hubspot Integration</h2>
          </div>
          <div class="px-6 py-4">
            <%= if @current_user.hubspot_access_token do %>
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <span class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-green-700 bg-green-100 rounded-full">
                    <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                    </svg>
                    Connected
                  </span>
                </div>
                <button
                  phx-click="disconnect_hubspot"
                  class="px-4 py-2 text-sm font-medium text-white bg-red-600 hover:bg-red-700 rounded-lg transition-colors"
                >
                  Disconnect Hubspot
                </button>
              </div>
            <% else %>
              <div class="text-center py-4">
                <p class="text-gray-600 mb-4">Connect your Hubspot account to access CRM features</p>
                <a
                  href="/auth/hubspot"
                  class="inline-flex items-center px-6 py-3 text-sm font-medium text-white bg-orange-600 hover:bg-orange-700 rounded-lg transition-colors"
                >
                  <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"/>
                  </svg>
                  Connect to Hubspot
                </a>
              </div>
            <% end %>
          </div>
        </div>

        <!-- AI Backend Section -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">AI Backend Configuration</h2>
          </div>
          <div class="px-6 py-4">
            <form phx-submit="save_settings" class="space-y-6">
              <!-- Model Selection -->
              <div>
                <label for="model" class="block text-sm font-medium text-gray-700 mb-2">
                  AI Model
                </label>
                <select
                  id="model"
                  name="model"
                  phx-change="update_model"
                  value={@selected_model}
                  class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <optgroup label="Self-Hosted Models">
                    <option value="self-hosted">Default (Self-Hosted)</option>
                  </optgroup>
                  <optgroup label="OpenAI Models">
                    <%= for model <- OpenAIModels.list_chat_models() do %>
                      <option value={Atom.to_string(model)}>
                        {OpenAIModels.to_string(model)}
                      </option>
                    <% end %>
                  </optgroup>
                </select>
                <p class="mt-2 text-sm text-gray-500">
                  Select the AI model to use for chat completions
                </p>
              </div>

              <!-- API Key Input (conditionally shown) -->
              <%= if @show_api_key_input do %>
                <div>
                  <label for="api_key" class="block text-sm font-medium text-gray-700 mb-2">
                    OpenAI API Key
                  </label>
                  <input
                    type="password"
                    id="api_key"
                    name="api_key"
                    value={@openai_api_key}
                    phx-change="update_api_key"
                    placeholder="sk-..."
                    class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  />
                  <p class="mt-2 text-sm text-gray-500">
                    Your API key is stored securely and only used for your requests
                  </p>
                </div>
              <% end %>

              <!-- Save Button -->
              <div class="flex justify-end">
                <button
                  type="submit"
                  class="px-6 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors"
                >
                  Save Settings
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
