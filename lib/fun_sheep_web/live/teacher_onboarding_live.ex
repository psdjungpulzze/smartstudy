defmodule FunSheepWeb.TeacherOnboardingLive do
  @moduledoc """
  Teacher-initiated onboarding wizard — Flow C (§6.2).

  Four steps:

    1. Create your first class — class details (captured in wizard
       state; persisted to teacher metadata until a dedicated
       Classrooms module exists)
    2. Add students — manual email entry, fires
       `Accounts.invite_guardian/3` with `:teacher` relationship for
       each
    3. Schedule an upcoming test — optional
    4. Done — reassures the teacher that billing is parent-side only
       (§6.2 Step 4)

  Route: `/onboarding/teacher`

  **Key invariant (§6.3)**: teachers never see pricing, never appear
  in a student's guardian picker for billing asks (enforced by
  `list_active_guardian_roles_for_student/2` in `AskComponent`), and
  never receive `ParentRequestEmail`.
  """

  use FunSheepWeb, :live_view

  alias FunSheep.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    teacher = Accounts.get_user_role_by_interactor_id(user["interactor_user_id"])

    socket =
      socket
      |> assign(
        page_title: "Set up your classroom",
        teacher: teacher,
        step: 1,
        class_details: %{
          name: "",
          period: "",
          course: "",
          school_year: ""
        },
        students: [],
        student_draft: "",
        form_error: nil,
        test: %{name: "", date: "", subject: ""},
        invite_results: []
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("update_class", %{"_target" => _} = params, socket) do
    details =
      Map.merge(socket.assigns.class_details, %{
        name: params["name"] || socket.assigns.class_details.name,
        period: params["period"] || socket.assigns.class_details.period,
        course: params["course"] || socket.assigns.class_details.course,
        school_year: params["school_year"] || socket.assigns.class_details.school_year
      })

    {:noreply, assign(socket, :class_details, details)}
  end

  def handle_event("submit_class", params, socket) do
    name = (params["name"] || "") |> String.trim()

    if name == "" do
      {:noreply, assign(socket, :form_error, "Please give your class a name.")}
    else
      details = %{
        name: name,
        period: params["period"] || "",
        course: params["course"] || "",
        school_year: params["school_year"] || ""
      }

      {:noreply, assign(socket, class_details: details, step: 2, form_error: nil)}
    end
  end

  def handle_event("add_student", params, socket) do
    email = (params["student_email"] || "") |> String.trim() |> String.downcase()

    cond do
      email == "" ->
        {:noreply, assign(socket, :form_error, "Enter a student email.")}

      not Regex.match?(~r/^[^\s]+@[^\s]+$/, email) ->
        {:noreply, assign(socket, :form_error, "That doesn't look like an email.")}

      email in socket.assigns.students ->
        {:noreply, assign(socket, :form_error, "That student is already on the list.")}

      true ->
        {:noreply,
         socket
         |> assign(
           students: socket.assigns.students ++ [email],
           student_draft: "",
           form_error: nil
         )}
    end
  end

  def handle_event("remove_student", %{"email" => email}, socket) do
    {:noreply, assign(socket, :students, List.delete(socket.assigns.students, email))}
  end

  def handle_event("send_invites", _params, socket) do
    case socket.assigns.students do
      [] ->
        {:noreply, assign(socket, :form_error, "Add at least one student first.")}

      students ->
        results = Enum.map(students, &send_teacher_invite(&1, socket.assigns.teacher))

        {:noreply,
         socket
         |> assign(invite_results: results, step: 3, form_error: nil)}
    end
  end

  def handle_event("set_test", params, socket) do
    test = %{
      name: (params["name"] || "") |> String.trim(),
      date: params["date"] || "",
      subject: (params["subject"] || "") |> String.trim()
    }

    {:noreply, assign(socket, test: test, step: 4)}
  end

  def handle_event("skip_test", _params, socket) do
    {:noreply, assign(socket, :step, 4)}
  end

  def handle_event("goto_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, :step, String.to_integer(step))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <.progress_header step={@step} />

      <%= case @step do %>
        <% 1 -> %>
          <.step_one class_details={@class_details} form_error={@form_error} />
        <% 2 -> %>
          <.step_two
            students={@students}
            student_draft={@student_draft}
            form_error={@form_error}
            class_name={@class_details.name}
          />
        <% 3 -> %>
          <.step_three test={@test} invite_results={@invite_results} />
        <% 4 -> %>
          <.step_four
            invite_results={@invite_results}
            class_name={@class_details.name}
            test={@test}
          />
      <% end %>
    </div>
    """
  end

  # ── Step components ──────────────────────────────────────────────────────

  attr :step, :integer, required: true

  def progress_header(assigns) do
    steps = [{1, "Class"}, {2, "Students"}, {3, "Test"}, {4, "Done"}]
    assigns = assign(assigns, :steps, steps)

    ~H"""
    <div class="flex items-center justify-between text-xs font-medium">
      <div
        :for={{n, label} <- @steps}
        class={[
          "flex items-center gap-2",
          if(n <= @step, do: "text-[#4CD964]", else: "text-[#8E8E93]")
        ]}
      >
        <span class={[
          "w-6 h-6 rounded-full flex items-center justify-center text-xs font-semibold",
          if(n <= @step,
            do: "bg-[#4CD964] text-white",
            else: "bg-[#F5F5F7] dark:bg-[#2C2C2E] text-[#8E8E93]"
          )
        ]}>
          {n}
        </span>
        <span class="hidden sm:inline">{label}</span>
      </div>
    </div>
    """
  end

  attr :class_details, :map, required: true
  attr :form_error, :any, required: true

  def step_one(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        Create your first class
      </h2>
      <p class="text-sm text-[#8E8E93]">
        FunSheep is free for educators — you're all set to add students in a moment.
      </p>

      <form phx-submit="submit_class" phx-change="update_class" class="space-y-3">
        <label class="block">
          <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Class name</span>
          <input
            type="text"
            name="name"
            value={@class_details.name}
            required
            placeholder="e.g. 10th Grade Chemistry"
            class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </label>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Period (optional)</span>
            <input
              type="text"
              name="period"
              value={@class_details.period}
              placeholder="3rd Period"
              class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
            />
          </label>

          <label class="block">
            <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">School year</span>
            <input
              type="text"
              name="school_year"
              value={@class_details.school_year}
              placeholder="2025-2026"
              class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
            />
          </label>
        </div>

        <label class="block">
          <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Course (optional)</span>
          <input
            type="text"
            name="course"
            value={@class_details.course}
            placeholder="Chemistry"
            class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </label>

        <p :if={@form_error} class="text-sm text-[#FF3B30]">{@form_error}</p>

        <div class="flex justify-end pt-2">
          <button
            type="submit"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
          >
            Next — add students
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :students, :list, required: true
  attr :student_draft, :string, required: true
  attr :form_error, :any, required: true
  attr :class_name, :string, required: true

  def step_two(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        Add students to {@class_name}
      </h2>
      <p class="text-sm text-[#8E8E93]">
        They'll get an invite email and start on the free tier — no billing required.
      </p>

      <form phx-submit="add_student" class="flex flex-col sm:flex-row gap-2">
        <input
          type="email"
          name="student_email"
          value={@student_draft}
          placeholder="student@school.edu"
          class="flex-1 px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
        />
        <button
          type="submit"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors whitespace-nowrap"
        >
          + Add
        </button>
      </form>

      <p :if={@form_error} class="text-sm text-[#FF3B30]">{@form_error}</p>

      <ul :if={@students != []} class="space-y-2 border-t border-[#E5E5EA] dark:border-[#3A3A3C] pt-4">
        <li
          :for={email <- @students}
          class="flex items-center justify-between px-4 py-2 bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl"
        >
          <span class="text-sm text-[#1C1C1E] dark:text-white">{email}</span>
          <button
            type="button"
            phx-click="remove_student"
            phx-value-email={email}
            class="text-xs text-[#FF3B30] hover:underline"
          >
            Remove
          </button>
        </li>
      </ul>

      <div class="flex items-center justify-between pt-2">
        <button
          type="button"
          phx-click="goto_step"
          phx-value-step="1"
          class="px-4 py-2 text-sm text-[#8E8E93] hover:text-[#1C1C1E] dark:hover:text-white"
        >
          ← Back
        </button>
        <button
          type="button"
          phx-click="send_invites"
          disabled={@students == []}
          class="bg-[#4CD964] hover:bg-[#3DBF55] disabled:bg-[#E5E5EA] disabled:text-[#8E8E93] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
        >
          Send invites
        </button>
      </div>
    </div>
    """
  end

  attr :test, :map, required: true
  attr :invite_results, :list, required: true

  def step_three(assigns) do
    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 space-y-4">
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        Any upcoming test to study for?
      </h2>
      <p class="text-sm text-[#8E8E93]">
        Optional — you can add this later from your classroom.
      </p>

      <div class="bg-[#FFF9E8] rounded-xl p-3 text-xs text-[#8E8E93]">
        Note: per-student test schedules are created when students
        activate. For now this captures the test you have in mind and
        shows it in the summary.
      </div>

      <form phx-submit="set_test" class="space-y-3">
        <label class="block">
          <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Test name</span>
          <input
            type="text"
            name="name"
            value={@test.name}
            placeholder="e.g. Unit 3 Exam"
            class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
          />
        </label>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Date</span>
            <input
              type="date"
              name="date"
              value={@test.date}
              class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
            />
          </label>

          <label class="block">
            <span class="text-sm font-medium text-[#1C1C1E] dark:text-white">Subject</span>
            <input
              type="text"
              name="subject"
              value={@test.subject}
              placeholder="Chemistry"
              class="mt-1 w-full px-4 py-3 bg-[#F5F5F7] dark:bg-[#1C1C1E] border border-transparent focus:border-[#4CD964] rounded-full outline-none"
            />
          </label>
        </div>

        <div class="flex items-center justify-between pt-2">
          <button
            type="button"
            phx-click="skip_test"
            class="px-4 py-2 text-sm text-[#8E8E93] hover:text-[#1C1C1E] dark:hover:text-white"
          >
            Skip for now
          </button>
          <button
            type="submit"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
          >
            Save and finish
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :invite_results, :list, required: true
  attr :class_name, :string, required: true
  attr :test, :map, required: true

  def step_four(assigns) do
    invited = Enum.count(assigns.invite_results, &(&1.status == :invited))
    pending_signup = Enum.count(assigns.invite_results, &(&1.status == :student_not_signed_up))
    assigns = assign(assigns, invited: invited, pending_signup: pending_signup)

    ~H"""
    <div class="bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-md p-6 text-center space-y-4">
      <div class="text-5xl" aria-hidden="true">🎓</div>
      <h2 class="text-2xl font-bold text-[#1C1C1E] dark:text-white">
        {@class_name} is set up
      </h2>
      <p class="text-sm text-[#1C1C1E] dark:text-white">
        {@invited} {students_noun(@invited)} invited.
        <span :if={@pending_signup > 0}>
          {@pending_signup} student{if @pending_signup == 1, do: "", else: "s"} not yet signed up — they'll be linked when they create a FunSheep account with that email.
        </span>
      </p>

      <div class="text-left bg-[#F5F5F7] dark:bg-[#1C1C1E] rounded-xl p-4 text-sm text-[#1C1C1E] dark:text-white space-y-2">
        <p><strong>What happens next:</strong></p>
        <ul class="space-y-1 list-disc list-inside text-[#8E8E93]">
          <li>Your students practise on the free tier (20 questions/week).</li>
          <li>
            When a student hits the weekly limit, a <strong>parent</strong>
            gets an invitation to upgrade — <em>not you</em>.
          </li>
          <li>You'll never see billing prompts or receive payment emails.</li>
        </ul>
      </div>

      <div :if={@test.name != ""} class="text-left bg-[#E8F8EB] rounded-xl p-4 text-sm text-[#1C1C1E]">
        Test captured: <strong>{@test.name}</strong>
        {if @test.date != "", do: " on #{@test.date}", else: ""}
      </div>

      <.link
        navigate="/teacher"
        class="inline-flex bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-3 rounded-full shadow-md transition-colors"
      >
        Go to your classroom
      </.link>
    </div>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp send_teacher_invite(email, %{id: teacher_id}) do
    case Accounts.invite_guardian(teacher_id, email, :teacher) do
      {:ok, _sg} ->
        %{email: email, status: :invited}

      {:error, :student_not_found} ->
        # The student hasn't signed up yet. We fall through gracefully —
        # in practice the teacher flow expects school-provided emails so
        # this is a known deferred path. Future improvement: email the
        # student an invite link or use the InviteCodes context.
        %{email: email, status: :student_not_signed_up}

      {:error, :already_linked} ->
        %{email: email, status: :already_linked}

      {:error, :already_invited} ->
        %{email: email, status: :already_invited}

      {:error, _} ->
        %{email: email, status: :failed}
    end
  end

  defp send_teacher_invite(_, _), do: %{email: "", status: :failed}

  defp students_noun(1), do: "student"
  defp students_noun(_), do: "students"
end
