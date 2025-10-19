defmodule AdvisorAgentWeb.ChatComponents do
  @moduledoc """
  Provides chat UI components for the chat interface.
  """
  use Phoenix.Component

  @doc """
  Renders the chat header with user info and connection status.
  """
  attr :current_user, :map, required: true

  def chat_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200">
      <h1 class="text-xl font-semibold text-gray-900">Ask Anything</h1>
      <div class="flex items-center gap-4">
        <span class="text-sm text-gray-600"><%= @current_user.email %></span>
        <%= if @current_user.hubspot_access_token do %>
          <span class="px-3 py-1.5 text-xs font-medium text-green-700 bg-green-100 rounded-full">
            Hubspot Connected
          </span>
        <% else %>
          <a href="/auth/hubspot" class="px-4 py-2 text-sm font-medium text-white bg-orange-600 hover:bg-orange-700 rounded-lg">
            Connect Hubspot
          </a>
        <% end %>
        <a href="/auth/logout" class="px-4 py-2 text-sm font-medium text-gray-700 hover:text-gray-900 hover:bg-gray-100 rounded-lg">
          Logout
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Renders the tab navigation with Chat and History tabs.
  """
  attr :active_tab, :atom, required: true

  def tab_nav(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-6 py-3 border-b border-gray-200">
      <div class="flex items-center gap-6">
        <button
          phx-click="switch_tab"
          phx-value-tab="chat"
          class={"text-sm font-medium pb-1 #{if @active_tab == :chat, do: "text-gray-900 border-b-2 border-gray-900", else: "text-gray-500 hover:text-gray-900"}"}>
          Chat
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="history"
          class={"text-sm font-medium pb-1 #{if @active_tab == :history, do: "text-gray-900 border-b-2 border-gray-900", else: "text-gray-500 hover:text-gray-900"}"}>
          History
        </button>
      </div>
      <button class="flex items-center gap-2 text-sm font-medium text-gray-700 hover:text-gray-900">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
        New thread
      </button>
    </div>
    """
  end

  @doc """
  Renders a single message bubble (user or agent).
  """
  attr :message, :map, required: true

  def message_bubble(assigns) do
    ~H"""
    <%= if @message.sender == :user do %>
      <div class="flex justify-end mb-6">
        <div class="bg-gray-100 rounded-2xl px-5 py-3 max-w-lg">
          <p class="text-gray-900 text-base"><%= @message.text %></p>
        </div>
      </div>
    <% else %>
      <div class="mb-6">
        <div class="text-gray-900 text-base max-w-2xl">
          <%= @message.text %>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Renders the message input form with toolbar.
  """
  attr :user_input, :string, required: true

  def chat_input(assigns) do
    ~H"""
    <div class="border-t border-gray-200 px-6 py-4">
      <form phx-submit="send_message" class="relative">
        <textarea
          class="w-full resize-none rounded-2xl border border-gray-300 px-4 py-3 pr-12 focus:outline-none focus:border-gray-400 text-base text-gray-900 placeholder-gray-400"
          rows="1"
          placeholder="Ask anything about your meetings..."
          name="user_message"
          phx-change="update_user_input"
          value={@user_input}
        ><%= @user_input %></textarea>
        <div class="absolute bottom-3 right-3 flex items-center gap-2">
          <button type="submit" class="p-2 bg-gray-900 hover:bg-gray-800 rounded-full">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 10l7-7m0 0l7 7m-7-7v18" />
            </svg>
          </button>
        </div>
      </form>

      <div class="flex items-center justify-between mt-3">
        <div class="flex items-center gap-2">
          <button class="p-2 hover:bg-gray-100 rounded-full">
            <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
          </button>
          <button class="flex items-center gap-1 px-3 py-1.5 text-sm border border-gray-300 rounded-full hover:bg-gray-50">
            <span>All meetings</span>
            <svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
            </svg>
          </button>
        </div>
        <div class="flex items-center gap-2">
          <button class="p-2 hover:bg-gray-100 rounded-full">
            <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.172 7l-6.344 6.344a1 1 0 01-1.414 0l-2.828-2.828a1 1 0 010-1.414l6.344-6.344a1 1 0 011.414 0l2.828 2.828a1 1 0 010 1.414z" />
            </svg>
          </button>
          <button class="p-2 hover:bg-gray-100 rounded-full">
            <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-14 0m7 10v-3" />
            </svg>
          </button>
          <button class="p-2 hover:bg-gray-100 rounded-full">
            <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11a7 7 0 01-14 0m7 10v-3" />
            </svg>
          </button>
        </div>
      </div>
    </div>
    """
  end
end
