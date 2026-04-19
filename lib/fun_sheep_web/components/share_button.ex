defmodule FunSheepWeb.ShareButton do
  @moduledoc """
  Reusable share button component using the Web Share API.

  Uses navigator.share() on mobile (iOS Safari, Android Chrome) for native
  share sheets. Falls back to clipboard copy with toast on desktop browsers.

  Supports four styles: `:button` (green primary), `:icon` (circle),
  `:compact` (small with label), and `:fab` (floating action button).
  """

  use Phoenix.Component

  @doc """
  Builds a full URL from a path using the endpoint configuration.
  """
  def share_url(path) do
    FunSheepWeb.Endpoint.url() <> path
  end

  @doc """
  Renders a share button that uses native sharing on mobile and clipboard on desktop.

  ## Attributes

    * `title` - The share title (used by native share dialog)
    * `text` - The share text/description
    * `url` - The URL to share (defaults to current page)
    * `style` - `:button` (default), `:icon`, `:compact`, or `:fab`
    * `label` - Button label text (default: "Share")
    * `class` - Additional CSS classes
  """

  attr :title, :string, required: true
  attr :text, :string, default: ""
  attr :url, :string, default: ""
  attr :style, :atom, default: :button
  attr :label, :string, default: "Share"
  attr :class, :string, default: ""

  def share_button(assigns) do
    ~H"""
    <%= case @style do %>
      <% :icon -> %>
        <button
          id={"share-btn-#{System.unique_integer([:positive])}"}
          phx-hook="NativeShare"
          data-share-title={@title}
          data-share-text={@text}
          data-share-url={@url}
          class={[
            "p-2.5 rounded-full border border-gray-200 bg-white hover:bg-gray-50",
            "text-gray-500 hover:text-gray-700 shadow-sm transition-colors touch-target",
            @class
          ]}
          aria-label="Share"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="w-4 h-4"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M7.217 10.907a2.25 2.25 0 1 0 0 2.186m0-2.186c.18.324.283.696.283 1.093s-.103.77-.283 1.093m0-2.186 9.566-5.314m-9.566 7.5 9.566 5.314m0 0a2.25 2.25 0 1 0 3.935 2.186 2.25 2.25 0 0 0-3.935-2.186Zm0-12.814a2.25 2.25 0 1 0 3.933-2.185 2.25 2.25 0 0 0-3.933 2.185Z"
            />
          </svg>
        </button>
      <% :compact -> %>
        <button
          id={"share-btn-#{System.unique_integer([:positive])}"}
          phx-hook="NativeShare"
          data-share-title={@title}
          data-share-text={@text}
          data-share-url={@url}
          class={[
            "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full",
            "text-xs font-medium text-gray-600 bg-white border border-gray-200",
            "hover:bg-gray-50 hover:text-gray-800 shadow-sm transition-colors touch-target",
            @class
          ]}
          aria-label="Share"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="w-3.5 h-3.5"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M7.217 10.907a2.25 2.25 0 1 0 0 2.186m0-2.186c.18.324.283.696.283 1.093s-.103.77-.283 1.093m0-2.186 9.566-5.314m-9.566 7.5 9.566 5.314m0 0a2.25 2.25 0 1 0 3.935 2.186 2.25 2.25 0 0 0-3.935-2.186Zm0-12.814a2.25 2.25 0 1 0 3.933-2.185 2.25 2.25 0 0 0-3.933 2.185Z"
            />
          </svg>
          {@label}
        </button>
      <% :fab -> %>
        <button
          id={"share-btn-#{System.unique_integer([:positive])}"}
          phx-hook="NativeShare"
          data-share-title={@title}
          data-share-text={@text}
          data-share-url={@url}
          class={[
            "w-12 h-12 rounded-full bg-[#4CD964] hover:bg-[#3DBF55] text-white",
            "shadow-lg flex items-center justify-center transition-colors touch-target",
            @class
          ]}
          aria-label="Share"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-5 h-5"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M7.217 10.907a2.25 2.25 0 1 0 0 2.186m0-2.186c.18.324.283.696.283 1.093s-.103.77-.283 1.093m0-2.186 9.566-5.314m-9.566 7.5 9.566 5.314m0 0a2.25 2.25 0 1 0 3.935 2.186 2.25 2.25 0 0 0-3.935-2.186Zm0-12.814a2.25 2.25 0 1 0 3.933-2.185 2.25 2.25 0 0 0-3.933 2.185Z"
            />
          </svg>
        </button>
      <% _ -> %>
        <button
          id={"share-btn-#{System.unique_integer([:positive])}"}
          phx-hook="NativeShare"
          data-share-title={@title}
          data-share-text={@text}
          data-share-url={@url}
          class={[
            "inline-flex items-center gap-2 px-5 py-2 rounded-full",
            "text-sm font-medium text-white bg-[#4CD964] hover:bg-[#3DBF55]",
            "shadow-md transition-colors touch-target",
            @class
          ]}
          aria-label="Share"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="w-4 h-4"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M7.217 10.907a2.25 2.25 0 1 0 0 2.186m0-2.186c.18.324.283.696.283 1.093s-.103.77-.283 1.093m0-2.186 9.566-5.314m-9.566 7.5 9.566 5.314m0 0a2.25 2.25 0 1 0 3.935 2.186 2.25 2.25 0 0 0-3.935-2.186Zm0-12.814a2.25 2.25 0 1 0 3.933-2.185 2.25 2.25 0 0 0-3.933 2.185Z"
            />
          </svg>
          {@label}
        </button>
    <% end %>
    """
  end
end
