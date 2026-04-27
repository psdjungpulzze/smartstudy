defmodule FunSheepWeb.Components.AdminSidebar do
  @moduledoc """
  Shared sidebar component for every `/admin/*` LiveView.

  Groups routes into Overview, Content, Operations, Interactor, and
  Settings so admins can find less-used pages (Job failures, Feature
  flags, Agents registry, etc.) without keeping a URL cheat sheet.

  Usage in a LiveView's render:

      <.admin_sidebar current_path={@current_path} />

  Requires the LiveView to assign `:current_path` — the existing
  `FunSheepWeb.LiveHelpers.save_request_path/3` hook (attached by the
  `:require_admin` on_mount hook) already does this.
  """
  use Phoenix.Component

  @sections [
    %{
      heading: nil,
      items: [
        %{label: "Overview", path: "/admin", icon: "🏠"}
      ]
    },
    %{
      heading: "Content",
      items: [
        %{label: "Users", path: "/admin/users", icon: "👥"},
        %{label: "Courses", path: "/admin/courses", icon: "📚"},
        %{label: "Materials", path: "/admin/materials", icon: "📖"},
        %{label: "Source health", path: "/admin/source-health", icon: "📊"},
        %{label: "Web pipeline", path: "/admin/web-pipeline", icon: "🔍"},
        %{label: "Question review", path: "/admin/questions/review", icon: "📝"},
        %{label: "Schools / geo", path: "/admin/geo", icon: "🌍"}
      ]
    },
    %{
      heading: "Operations",
      items: [
        %{label: "AI usage", path: "/admin/usage/ai", icon: "💸"},
        %{label: "Job failures", path: "/admin/jobs/failures", icon: "⚠"},
        %{label: "Background jobs", path: "/admin/jobs", icon: "⚙", external: true},
        %{label: "System health", path: "/admin/health", icon: "❤"},
        %{label: "Feature flags", path: "/admin/flags", icon: "🎛"},
        %{label: "Billing", path: "/admin/billing", icon: "💳"}
      ]
    },
    %{
      heading: "Interactor",
      items: [
        %{label: "Agents", path: "/admin/interactor/agents", icon: "🤖"},
        %{label: "Credentials", path: "/admin/interactor/credentials", icon: "🔑"},
        %{label: "Profiles", path: "/admin/interactor/profiles", icon: "👤"}
      ]
    },
    %{
      heading: "Settings",
      items: [
        %{label: "Audit log", path: "/admin/audit-log", icon: "🛡"},
        %{label: "MFA", path: "/admin/settings/mfa", icon: "🔒"}
      ]
    }
  ]

  attr :current_path, :any, default: nil

  @doc """
  Renders the vertical admin sidebar. Active link is highlighted with the
  brand-green background chip defined in the UI design rules.
  """
  def admin_sidebar(assigns) do
    assigns = assign(assigns, :sections, @sections)

    ~H"""
    <aside class="hidden lg:flex flex-col w-56 shrink-0 bg-white border-r border-[#E5E5EA] min-h-screen sticky top-0">
      <div class="px-4 py-4 border-b border-[#F5F5F7]">
        <div class="text-xs uppercase tracking-wide text-[#8E8E93] font-semibold">
          Admin
        </div>
      </div>
      <nav class="flex-1 overflow-y-auto py-2">
        <.section :for={section <- @sections} section={section} current_path={@current_path} />
      </nav>
    </aside>
    """
  end

  attr :section, :map, required: true
  attr :current_path, :any, required: true

  defp section(assigns) do
    ~H"""
    <div class="py-1">
      <h4
        :if={@section.heading}
        class="text-[10px] uppercase tracking-wide text-[#8E8E93] font-semibold px-4 pt-3 pb-1"
      >
        {@section.heading}
      </h4>
      <ul class="space-y-0.5">
        <li :for={item <- @section.items}>
          <.item item={item} current_path={@current_path} />
        </li>
      </ul>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :current_path, :any, required: true

  defp item(assigns) do
    active? = assigns.current_path == assigns.item.path
    external? = Map.get(assigns.item, :external, false)

    class =
      "flex items-center gap-2 mx-2 px-3 py-1.5 rounded-xl text-sm transition-colors " <>
        if(active?,
          do: "bg-[#E8F8EB] text-[#3DBF55] font-medium",
          else: "text-[#1C1C1E] hover:bg-[#F5F5F7]"
        )

    assigns = assign(assigns, active?: active?, external?: external?, class: class)

    ~H"""
    <%= if @external? do %>
      <a href={@item.path} class={@class}>
        <span class="w-4 text-center">{@item.icon}</span>
        <span>{@item.label}</span>
      </a>
    <% else %>
      <.link navigate={@item.path} class={@class}>
        <span class="w-4 text-center">{@item.icon}</span>
        <span>{@item.label}</span>
      </.link>
    <% end %>
    """
  end
end
