defmodule FunSheepWeb.DevLoginLive do
  use FunSheepWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dev Login"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 via-white to-indigo-50 flex items-center justify-center p-6">
      <div class="w-full max-w-lg animate-slide-up">
        <%!-- Logo / Header --%>
        <div class="text-center mb-10">
          <div class="inline-block animate-float">
            <span class="text-7xl">🐑</span>
          </div>
          <h1 class="text-3xl font-extrabold text-gray-900 mt-3">Fun Sheep</h1>
          <p class="text-gray-500 mt-2 text-sm">
            Dev Mode &mdash; Pick a role to jump in
          </p>
        </div>

        <%!-- Role Cards Grid --%>
        <div class="grid grid-cols-2 gap-4">
          <.role_card role="student" title="Student" emoji="🎒" description="Courses, tests & study guides" color="purple" />
          <.role_card role="parent" title="Parent" emoji="👨‍👩‍👧" description="Track your kid's progress" color="indigo" />
          <.role_card role="teacher" title="Teacher" emoji="🎓" description="Classes, students & content" color="amber" />
          <.role_card role="admin" title="Admin" emoji="⚙️" description="Full system access" color="rose" />
        </div>

        <p class="text-center text-xs text-gray-400 mt-8">
          Dev only. Production uses Interactor auth.
        </p>
      </div>
    </div>
    """
  end

  attr :role, :string, required: true
  attr :title, :string, required: true
  attr :emoji, :string, required: true
  attr :description, :string, required: true
  attr :color, :string, required: true

  defp role_card(assigns) do
    ~H"""
    <form action="/dev/auth" method="post" class="group">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="role" value={@role} />
      <button
        type="submit"
        class="w-full bg-white rounded-2xl shadow-sm p-6 text-center transition-all card-hover cursor-pointer border border-gray-100 hover:border-purple-200 focus:outline-none focus:ring-2 focus:ring-purple-400"
      >
        <span class="text-4xl block mb-3">{@emoji}</span>
        <h3 class="font-bold text-gray-900">{@title}</h3>
        <p class="text-xs text-gray-500 mt-1">{@description}</p>
      </button>
    </form>
    """
  end
end
