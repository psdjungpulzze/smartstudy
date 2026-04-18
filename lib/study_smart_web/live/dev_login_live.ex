defmodule StudySmartWeb.DevLoginLive do
  use StudySmartWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dev Login"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F5F5F7] flex items-center justify-center p-6">
      <div class="w-full max-w-lg">
        <%!-- Logo / Header --%>
        <div class="text-center mb-10">
          <div class="inline-flex items-center justify-center w-16 h-16 bg-[#4CD964] rounded-2xl mb-4">
            <svg
              class="w-8 h-8 text-white"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M4.26 10.147a60.438 60.438 0 0 0-.491 6.347A48.62 48.62 0 0 1 12 20.904a48.62 48.62 0 0 1 8.232-4.41 60.46 60.46 0 0 0-.491-6.347m-15.482 0a50.636 50.636 0 0 0-2.658-.813A59.906 59.906 0 0 1 12 3.493a59.903 59.903 0 0 1 10.399 5.84c-.896.248-1.783.52-2.658.814m-15.482 0A50.717 50.717 0 0 1 12 13.489a50.702 50.702 0 0 1 7.74-3.342"
              />
            </svg>
          </div>
          <h1 class="text-3xl font-bold text-[#1C1C1E]">StudySmart</h1>
          <p class="text-[#8E8E93] mt-2 text-sm">
            Development Login &mdash; Select a role to continue
          </p>
        </div>

        <%!-- Role Cards Grid --%>
        <div class="grid grid-cols-2 gap-4">
          <%!-- Student --%>
          <.role_card
            role="student"
            title="Student"
            description="Access courses, assessments, and study guides"
            icon_path="M4.26 10.147a60.438 60.438 0 0 0-.491 6.347A48.62 48.62 0 0 1 12 20.904a48.62 48.62 0 0 1 8.232-4.41 60.46 60.46 0 0 0-.491-6.347m-15.482 0a50.636 50.636 0 0 0-2.658-.813A59.906 59.906 0 0 1 12 3.493a59.903 59.903 0 0 1 10.399 5.84c-.896.248-1.783.52-2.658.814m-15.482 0A50.717 50.717 0 0 1 12 13.489a50.702 50.702 0 0 1 7.74-3.342"
            color="bg-blue-50 text-blue-600"
          />

          <%!-- Parent --%>
          <.role_card
            role="parent"
            title="Parent"
            description="Monitor children's progress and reports"
            icon_path="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z"
            color="bg-purple-50 text-purple-600"
          />

          <%!-- Teacher --%>
          <.role_card
            role="teacher"
            title="Teacher"
            description="Manage classes, students, and create content"
            icon_path="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
            color="bg-amber-50 text-amber-600"
          />

          <%!-- Admin --%>
          <.role_card
            role="admin"
            title="Admin"
            description="Full system administration and settings"
            icon_path="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
            color="bg-red-50 text-red-600"
          />
        </div>

        <p class="text-center text-xs text-[#8E8E93] mt-8">
          This login is for development only. Production uses Interactor authentication.
        </p>
      </div>
    </div>
    """
  end

  attr :role, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon_path, :string, required: true
  attr :color, :string, required: true

  defp role_card(assigns) do
    ~H"""
    <form action="/dev/auth" method="post" class="group">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="role" value={@role} />
      <button
        type="submit"
        class="w-full bg-white rounded-2xl shadow-md p-6 text-left transition-all hover:shadow-lg hover:scale-[1.02] cursor-pointer border border-transparent hover:border-[#4CD964] focus:outline-none focus:ring-2 focus:ring-[#4CD964]"
      >
        <div class={"inline-flex items-center justify-center w-10 h-10 rounded-lg mb-3 #{@color}"}>
          <svg
            class="w-5 h-5"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d={@icon_path} />
          </svg>
        </div>
        <h3 class="font-semibold text-[#1C1C1E] text-base">{@title}</h3>
        <p class="text-xs text-[#8E8E93] mt-1">{@description}</p>
      </button>
    </form>
    """
  end
end
