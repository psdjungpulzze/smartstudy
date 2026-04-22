defmodule FunSheepWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FunSheepWeb, :html

  import FunSheepWeb.GamificationModals

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  Maps hero icon names to fun emoji for the teen-friendly sidebar.
  """
  def nav_emoji("hero-home"), do: "🏠"
  def nav_emoji("hero-book-open"), do: "📚"
  def nav_emoji("hero-clipboard-document-check"), do: "📝"
  def nav_emoji("hero-bolt"), do: "⚡"
  def nav_emoji("hero-document-text"), do: "📖"
  def nav_emoji("hero-users"), do: "👥"
  def nav_emoji("hero-chart-bar"), do: "📊"
  def nav_emoji("hero-academic-cap"), do: "🎓"
  def nav_emoji("hero-user-group"), do: "👨‍🎓"
  def nav_emoji("hero-building-library"), do: "🏫"
  def nav_emoji("hero-cog-6-tooth"), do: "⚙️"
  def nav_emoji("hero-trophy"), do: "🏆"
  def nav_emoji("hero-user"), do: "👤"
  def nav_emoji(_), do: "✨"

  @doc """
  Returns navigation items for a given role.
  """
  def nav_items_for_role(role) do
    case role do
      "student" ->
        [
          %{label: "Learn", path: "/dashboard", icon: "hero-home"},
          %{label: "Courses", path: "/courses", icon: "hero-book-open"},
          %{label: "Practice", path: "/practice", icon: "hero-bolt"},
          %{label: "Flocks", path: "/leaderboard", icon: "hero-trophy"}
        ]

      "parent" ->
        [
          %{label: "Home", path: "/parent", icon: "hero-home"},
          %{label: "Children", path: "/parent/children", icon: "hero-users"},
          %{label: "Reports", path: "/parent/reports", icon: "hero-chart-bar"}
        ]

      "teacher" ->
        [
          %{label: "Home", path: "/teacher", icon: "hero-home"},
          %{label: "My Classes", path: "/teacher/classes", icon: "hero-academic-cap"},
          %{label: "Students", path: "/teacher/students", icon: "hero-user-group"},
          %{label: "Reports", path: "/teacher/reports", icon: "hero-chart-bar"}
        ]

      # Primary nav is capped at 5 items so it fits the mobile bottom-tab
      # bar and the tablet header without overflow. Jobs + Audit + MFA
      # settings are reachable from the dashboard tiles instead.
      "admin" ->
        [
          %{label: "Home", path: "/admin", icon: "hero-home"},
          %{label: "Users", path: "/admin/users", icon: "hero-users"},
          %{label: "Courses", path: "/admin/courses", icon: "hero-book-open"},
          %{label: "Materials", path: "/admin/materials", icon: "hero-document-text"},
          %{
            label: "Review",
            path: "/admin/questions/review",
            icon: "hero-clipboard-document-check"
          }
        ]

      _ ->
        [
          %{label: "Home", path: "/dashboard", icon: "hero-home"}
        ]
    end
  end

  @total_profile_items 2

  @doc """
  Returns profile completion percentage based on gaps.
  """
  def profile_completion_pct(gaps) when is_list(gaps) do
    completed = @total_profile_items - length(gaps)
    round(completed / @total_profile_items * 100)
  end

  def profile_completion_pct(_), do: 100

  @doc """
  Returns a contextual nudge message based on what's missing.
  """
  def profile_nudge_message(gaps) when is_list(gaps) do
    cond do
      :grade in gaps and :hobbies in gaps ->
        "Tell us your grade level and hobbies so we can personalize your questions and match you with peers."

      :grade in gaps ->
        "Add your grade level so we can find the right difficulty for you."

      :hobbies in gaps ->
        "Pick your hobbies and we'll weave them into practice questions to make studying more fun!"

      true ->
        "A few more details will help us personalize your experience."
    end
  end

  def profile_nudge_message(_), do: ""
end
