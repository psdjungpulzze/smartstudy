defmodule FunSheepWeb.TeacherDashboardLive do
  use FunSheepWeb, :live_view

  alias FunSheep.{Accounts, Assessments, Credits, Questions}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {user_role_id, students} =
      case Accounts.get_user_role_by_interactor_id(user["interactor_user_id"]) do
        nil ->
          {nil, []}

        user_role ->
          students =
            user_role.id
            |> Accounts.list_students_for_guardian()
            |> Enum.map(fn sg -> enrich_student(sg.student) end)

          {user_role.id, students}
      end

    {credits_balance, credit_progress, credit_ledger} =
      if user_role_id do
        {
          Credits.get_balance(user_role_id),
          Credits.credit_progress(user_role_id),
          Credits.list_ledger(user_role_id, limit: 10)
        }
      else
        {0, nil, []}
      end

    creator_stats =
      if user_role_id do
        Questions.creator_stats(user_role_id)
      else
        %{total_contributed: 0, passed: 0, pending: 0, failed: 0, by_course: []}
      end

    socket =
      socket
      |> assign(
        page_title: "Teacher Dashboard",
        user_role_id: user_role_id,
        students: students,
        sort_by: :name,
        sort_dir: :asc,
        expanded_student_id: nil,
        expanded_concepts: [],
        credits_balance: credits_balance,
        credit_progress: credit_progress,
        credit_ledger: credit_ledger,
        give_credit_open: false,
        give_credit_search: "",
        give_credit_results: [],
        give_credit_recipient: nil,
        give_credit_note: "",
        give_credit_error: nil,
        give_credit_success: nil,
        creator_stats: creator_stats
      )
      |> FunSheepWeb.LiveHelpers.assign_tutorial(
        key: "teacher_dashboard",
        title: "Welcome to your classroom",
        subtitle: "A quick look at what's here.",
        steps: [
          %{
            emoji: "👥",
            title: "Your students",
            body: "Every student you've invited appears here with their readiness."
          },
          %{
            emoji: "📈",
            title: "Sort + filter",
            body: "Sort by readiness to find students who need attention."
          },
          %{
            emoji: "🔍",
            title: "Drill down",
            body: "Click any student row to see their concept-level breakdown."
          }
        ]
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("sort", %{"field" => "readiness"}, socket) do
    new_dir =
      if socket.assigns.sort_by == :readiness,
        do: toggle_dir(socket.assigns.sort_dir),
        else: :desc

    sorted =
      Enum.sort_by(socket.assigns.students, & &1.readiness_score, fn a, b ->
        case new_dir do
          :asc -> (a || -1) <= (b || -1)
          :desc -> (a || -1) >= (b || -1)
        end
      end)

    {:noreply, assign(socket, students: sorted, sort_by: :readiness, sort_dir: new_dir)}
  end

  def handle_event("toggle_student", %{"id" => student_id}, socket) do
    if socket.assigns.expanded_student_id == student_id do
      {:noreply, assign(socket, expanded_student_id: nil, expanded_concepts: [])}
    else
      student = Enum.find(socket.assigns.students, &(&1.id == student_id))
      concepts = if student && student.test_schedule_id, do: load_concepts(student), else: []
      {:noreply, assign(socket, expanded_student_id: student_id, expanded_concepts: concepts)}
    end
  end

  def handle_event("toggle_give_credit", _params, socket) do
    {:noreply,
     assign(socket,
       give_credit_open: !socket.assigns.give_credit_open,
       give_credit_search: "",
       give_credit_results: [],
       give_credit_recipient: nil,
       give_credit_error: nil,
       give_credit_success: nil
     )}
  end

  def handle_event("search_recipients", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Accounts.list_users_for_admin(search: query, limit: 5)
      else
        []
      end

    {:noreply, assign(socket, give_credit_search: query, give_credit_results: results)}
  end

  def handle_event("select_recipient", %{"id" => recipient_id}, socket) do
    recipient = Accounts.get_user_role!(recipient_id)

    {:noreply,
     assign(socket,
       give_credit_recipient: recipient,
       give_credit_results: [],
       give_credit_search: recipient.display_name || recipient.email
     )}
  end

  def handle_event("give_credit_submit", %{"note" => note}, socket) do
    from_id = socket.assigns.user_role_id
    recipient = socket.assigns.give_credit_recipient
    balance = socket.assigns.credits_balance

    cond do
      is_nil(recipient) ->
        {:noreply, assign(socket, give_credit_error: "Please select a recipient.")}

      balance < 1 ->
        {:noreply, assign(socket, give_credit_error: "You don't have enough credits.")}

      true ->
        case Credits.transfer_credits(from_id, recipient.id, 1, note) do
          {:ok, _transfer} ->
            new_balance = Credits.get_balance(from_id)
            new_ledger = Credits.list_ledger(from_id, limit: 10)

            {:noreply,
             assign(socket,
               credits_balance: new_balance,
               credit_ledger: new_ledger,
               give_credit_open: false,
               give_credit_recipient: nil,
               give_credit_search: "",
               give_credit_note: "",
               give_credit_error: nil,
               give_credit_success:
                 "1 credit given to #{recipient.display_name || recipient.email}!"
             )}

          {:error, :insufficient_balance} ->
            {:noreply, assign(socket, give_credit_error: "Insufficient balance.")}

          {:error, :invalid_recipient} ->
            {:noreply, assign(socket, give_credit_error: "That recipient is not available.")}

          {:error, _} ->
            {:noreply,
             assign(socket, give_credit_error: "Something went wrong. Please try again.")}
        end
    end
  end

  # --- Data loading ----------------------------------------------------------

  defp enrich_student(user_role) do
    primary_test = Assessments.primary_test(user_role.id)
    readiness = if primary_test, do: Assessments.latest_readiness(user_role.id, primary_test.id)
    last_active = Assessments.last_active(user_role.id)

    {readiness_score, weak_count, state, test_name, test_schedule_id} =
      case readiness do
        nil ->
          {nil, 0, :untested, primary_test && primary_test.name, primary_test && primary_test.id}

        r ->
          score = round(r.aggregate_score)
          weak = count_weak_concepts(r)
          st = readiness_state(r)
          {score, weak, st, primary_test.name, primary_test.id}
      end

    %{
      id: user_role.id,
      name: user_role.display_name || user_role.email,
      email: user_role.email,
      grade: user_role.grade,
      readiness_score: readiness_score,
      weak_count: weak_count,
      state: state,
      test_name: test_name,
      test_schedule_id: test_schedule_id,
      last_active: last_active
    }
  end

  defp load_concepts(%{id: student_id, test_schedule_id: schedule_id}) do
    Assessments.topic_mastery_map(student_id, schedule_id)
    |> Enum.flat_map(fn chapter ->
      Enum.map(chapter.topics, fn t ->
        Map.put(t, :chapter_name, chapter.chapter_name)
      end)
    end)
    |> Enum.sort_by(& &1.accuracy)
  end

  defp count_weak_concepts(nil), do: 0

  defp count_weak_concepts(readiness) do
    (readiness.skill_scores || %{})
    |> Map.values()
    |> Enum.count(fn s -> s[:status] in [:weak, :probing] end)
  end

  defp readiness_state(nil), do: :untested

  defp readiness_state(readiness) do
    scores = readiness.skill_scores || %{}
    tested = Enum.count(scores, fn {_, s} -> s[:status] != :insufficient_data end)

    cond do
      tested == 0 -> :untested
      readiness.coverage_pct < 100 -> :in_progress
      true -> :complete
    end
  end

  # --- Helpers ---------------------------------------------------------------

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp state_label(:untested), do: "Not started"
  defp state_label(:in_progress), do: "In progress"
  defp state_label(:complete), do: "Complete"

  defp state_badge(:untested), do: "bg-[#F5F5F7] text-[#8E8E93]"
  defp state_badge(:in_progress), do: "bg-[#FFF8E1] text-[#FF9500]"
  defp state_badge(:complete), do: "bg-[#E8F8EB] text-[#4CD964]"

  defp readiness_text_color(score) when score > 70, do: "text-[#4CD964]"
  defp readiness_text_color(score) when score >= 40, do: "text-[#FF9500]"
  defp readiness_text_color(_score), do: "text-[#FF3B30]"

  defp concept_status_badge(:mastered), do: {"Ready", "bg-[#E8F8EB] text-[#4CD964]"}
  defp concept_status_badge(:probing), do: {"Needs Work", "bg-[#FFF8E1] text-[#FF9500]"}
  defp concept_status_badge(:weak), do: {"Focus Here", "bg-[#FFE5E3] text-[#FF3B30]"}
  defp concept_status_badge(_), do: {"Not Tested", "bg-[#F5F5F7] text-[#8E8E93]"}

  defp format_last_active(nil), do: "Never"

  defp format_last_active(%DateTime{} = dt) do
    now = DateTime.utc_now()
    days = DateTime.diff(now, dt, :day)

    cond do
      days == 0 -> "Today"
      days == 1 -> "Yesterday"
      days < 7 -> "#{days} days ago"
      days < 30 -> "#{div(days, 7)} weeks ago"
      true -> "#{div(days, 30)} months ago"
    end
  end

  defp format_last_active(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> format_last_active()
  end

  defp class_distribution(students) do
    Enum.group_by(students, & &1.state)
    |> Map.new(fn {k, v} -> {k, length(v)} end)
  end

  defp calculate_avg_readiness(students) do
    scores = students |> Enum.filter(& &1.readiness_score) |> Enum.map(& &1.readiness_score)

    case scores do
      [] -> nil
      scores -> Enum.sum(scores) |> div(length(scores))
    end
  end

  defp needs_attention(students) do
    students
    |> Enum.filter(fn s ->
      s.state == :untested or
        (s.state == :in_progress and s.weak_count > 0) or
        is_nil(s.last_active) or
        (s.last_active &&
           DateTime.diff(DateTime.utc_now(), maybe_utc(s.last_active), :day) > 7)
    end)
    |> Enum.sort_by(fn s ->
      {if(s.state == :untested, do: 0, else: 1), s.weak_count * -1}
    end)
    |> Enum.take(5)
  end

  defp maybe_utc(%DateTime{} = dt), do: dt
  defp maybe_utc(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  # --- Render ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    avg_readiness = calculate_avg_readiness(assigns.students)
    dist = class_distribution(assigns.students)
    attention = needs_attention(assigns.students)
    assigns = assign(assigns, avg_readiness: avg_readiness, dist: dist, attention: attention)

    ~H"""
    <div>
      <h1 class="text-2xl font-bold text-[#1C1C1E]">Teacher Dashboard</h1>
      <p class="text-[#8E8E93] mt-2">Welcome, {@current_user["display_name"]}</p>

      <%!-- Class summary cards --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-8">
        <div class="bg-white rounded-2xl shadow-md p-5 text-center">
          <p class="text-3xl font-bold text-[#4CD964]">{length(@students)}</p>
          <p class="text-xs text-[#8E8E93] mt-1">Total Students</p>
        </div>
        <div class="bg-white rounded-2xl shadow-md p-5 text-center">
          <%= if @avg_readiness do %>
            <p class={"text-3xl font-bold #{readiness_text_color(@avg_readiness)}"}>
              {@avg_readiness}%
            </p>
          <% else %>
            <p class="text-3xl font-bold text-[#8E8E93]">—</p>
          <% end %>
          <p class="text-xs text-[#8E8E93] mt-1">Avg Readiness</p>
        </div>
        <div class="bg-white rounded-2xl shadow-md p-5 text-center">
          <p class="text-3xl font-bold text-[#FF9500]">{Map.get(@dist, :in_progress, 0)}</p>
          <p class="text-xs text-[#8E8E93] mt-1">In Progress</p>
        </div>
        <div class="bg-white rounded-2xl shadow-md p-5 text-center">
          <p class="text-3xl font-bold text-[#FF3B30]">{Map.get(@dist, :untested, 0)}</p>
          <p class="text-xs text-[#8E8E93] mt-1">Not Started</p>
        </div>
      </div>

      <%!-- Needs attention panel --%>
      <%= if @attention != [] do %>
        <div class="bg-[#FFF8E1] border border-[#FFCC00] rounded-2xl p-5 mt-6">
          <h3 class="text-sm font-semibold text-[#1C1C1E] mb-3 flex items-center gap-2">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-[#FF9500]" /> Needs Attention
          </h3>
          <div class="flex flex-wrap gap-2">
            <span
              :for={s <- @attention}
              class="text-xs bg-white border border-[#E5E5EA] rounded-full px-3 py-1 text-[#1C1C1E]"
            >
              {s.name}
              <%= if s.state == :untested do %>
                · not started
              <% else %>
                · {s.weak_count} weak
              <% end %>
            </span>
          </div>
        </div>
      <% end %>

      <%= if @students == [] do %>
        <div class="bg-white rounded-2xl shadow-md p-8 mt-8 text-center">
          <.icon name="hero-user-group" class="w-12 h-12 text-[#8E8E93] mx-auto mb-4" />
          <p class="text-[#8E8E93] text-lg">
            No students linked yet. Add students to start monitoring their progress.
          </p>
          <.link
            navigate={~p"/guardians"}
            class="inline-block mt-6 bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Students
          </.link>
        </div>
      <% else %>
        <div class="flex justify-end mt-6 gap-3">
          <.link
            navigate={~p"/guardians"}
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Add Students
          </.link>
        </div>

        <%!-- Student table --%>
        <div class="bg-white rounded-2xl shadow-md mt-4 overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-[#E5E5EA]">
                <th class="text-left px-6 py-4 text-xs font-semibold text-[#8E8E93] uppercase tracking-wide">
                  Student
                </th>
                <th class="text-left px-6 py-4 text-xs font-semibold text-[#8E8E93] uppercase tracking-wide">
                  Test
                </th>
                <th class="text-left px-6 py-4 text-xs font-semibold text-[#8E8E93] uppercase tracking-wide">
                  Status
                </th>
                <th
                  class="text-left px-6 py-4 text-xs font-semibold text-[#8E8E93] uppercase tracking-wide cursor-pointer hover:text-[#4CD964]"
                  phx-click="sort"
                  phx-value-field="readiness"
                >
                  Readiness
                  <%= if @sort_by == :readiness do %>
                    <span class="ml-1">{if @sort_dir == :asc, do: "▲", else: "▼"}</span>
                  <% end %>
                </th>
                <th class="text-left px-6 py-4 text-xs font-semibold text-[#8E8E93] uppercase tracking-wide">
                  Weak Concepts
                </th>
                <th class="text-left px-6 py-4 text-xs font-semibold text-[#8E8E93] uppercase tracking-wide">
                  Last Active
                </th>
              </tr>
            </thead>
            <tbody>
              <tbody :for={student <- @students}>
                <%!-- Main student row --%>
                <tr
                  class="border-b border-[#E5E5EA] hover:bg-[#F5F5F7] cursor-pointer transition-colors"
                  phx-click="toggle_student"
                  phx-value-id={student.id}
                >
                  <td class="px-6 py-4">
                    <p class="text-sm font-medium text-[#1C1C1E]">{student.name}</p>
                    <p class="text-xs text-[#8E8E93]">{student.email}</p>
                  </td>
                  <td class="px-6 py-4 text-sm text-[#8E8E93]">
                    {student.test_name || "—"}
                  </td>
                  <td class="px-6 py-4">
                    <span class={"text-xs font-medium px-3 py-1 rounded-full #{state_badge(student.state)}"}>
                      {state_label(student.state)}
                    </span>
                  </td>
                  <td class="px-6 py-4">
                    <%= if student.readiness_score do %>
                      <span class={"text-sm font-bold #{elem(readiness_badge_colors(student.readiness_score), 0)}"}>
                        {student.readiness_score}%
                      </span>
                    <% else %>
                      <span class="text-sm text-[#8E8E93]">—</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4">
                    <%= if student.weak_count > 0 do %>
                      <span class="text-sm font-semibold text-[#FF3B30]">{student.weak_count}</span>
                    <% else %>
                      <span class="text-sm text-[#8E8E93]">0</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 text-sm text-[#8E8E93]">
                    {format_last_active(student.last_active)}
                  </td>
                </tr>

                <%!-- Concept drill-down (expanded) --%>
                <%= if @expanded_student_id == student.id do %>
                  <tr class="border-b border-[#E5E5EA]">
                    <td colspan="6" class="px-6 py-4 bg-[#F5F5F7]">
                      <%= if @expanded_concepts == [] do %>
                        <p class="text-sm text-[#8E8E93] py-2">
                          No concept data yet — student hasn't been assessed.
                        </p>
                      <% else %>
                        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 max-h-80 overflow-y-auto">
                          <div
                            :for={concept <- @expanded_concepts}
                            class="flex items-center gap-3 bg-white rounded-xl px-4 py-2.5 shadow-sm"
                          >
                            <div class="flex-1 min-w-0">
                              <p class="text-xs font-medium text-[#1C1C1E] truncate">
                                {concept.section_name}
                              </p>
                              <p class="text-xs text-[#8E8E93] truncate">{concept.chapter_name}</p>
                            </div>
                            <div class="flex items-center gap-2 shrink-0">
                              <%= if concept.attempts_count > 0 do %>
                                <span class="text-xs font-semibold text-[#1C1C1E]">
                                  {round(concept.accuracy)}%
                                </span>
                              <% end %>
                              <span class={"text-xs font-medium px-2 py-0.5 rounded-full #{elem(concept_status_badge(concept.status), 1)}"}>
                                {elem(concept_status_badge(concept.status), 0)}
                              </span>
                            </div>
                          </div>
                        </div>
                        <p class="text-xs text-[#8E8E93] mt-3">
                          {length(@expanded_concepts)} concepts · sorted weakest first
                        </p>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </tbody>
          </table>
        </div>
      <% end %>

      <%!-- Creator Metrics Card --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mt-8">
        <h2 class="text-lg font-semibold text-[#1C1C1E] mb-4 flex items-center gap-2">
          <.icon name="hero-book-open" class="w-5 h-5 text-[#4CD964]" /> My Contributions
        </h2>

        <%= if @creator_stats.total_contributed == 0 do %>
          <p class="text-sm text-[#8E8E93]">
            No questions attributed to your uploads yet. Upload course materials to contribute questions.
          </p>
        <% else %>
          <%!-- Summary counts --%>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
            <div class="bg-[#F5F5F7] rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-[#1C1C1E]">{@creator_stats.total_contributed}</p>
              <p class="text-xs text-[#8E8E93] mt-1">Total Questions</p>
            </div>
            <div class="bg-[#E8F8EB] rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-[#4CD964]">{@creator_stats.passed}</p>
              <p class="text-xs text-[#8E8E93] mt-1">Approved</p>
            </div>
            <div class="bg-[#FFF8E1] rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-[#FF9500]">{@creator_stats.pending}</p>
              <p class="text-xs text-[#8E8E93] mt-1">Pending</p>
            </div>
            <div class="bg-[#FFE5E3] rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-[#FF3B30]">{@creator_stats.failed}</p>
              <p class="text-xs text-[#8E8E93] mt-1">Rejected</p>
            </div>
          </div>

          <%!-- Per-course breakdown --%>
          <%= if @creator_stats.by_course != [] do %>
            <div>
              <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
                By Course
              </p>
              <ul class="space-y-2">
                <li
                  :for={entry <- @creator_stats.by_course}
                  class="flex items-center justify-between text-sm bg-[#F5F5F7] rounded-xl px-4 py-2.5"
                >
                  <div class="min-w-0">
                    <p class="font-medium text-[#1C1C1E] truncate">{entry.course_name}</p>
                    <p class="text-xs text-[#8E8E93]">
                      {entry.course_subject} · Grade {entry.course_grade}
                    </p>
                  </div>
                  <span class="text-xs font-semibold text-[#4CD964] bg-[#E8F8EB] rounded-full px-3 py-1 ml-3 shrink-0">
                    {entry.question_count} {if entry.question_count == 1, do: "question",
                      else: "questions"}
                  </span>
                </li>
              </ul>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Wool Credits Card --%>
      <div class="bg-white rounded-2xl shadow-md p-6 mt-8">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-[#1C1C1E] flex items-center gap-2">
            🧶 Wool Credits
          </h2>
          <span class="text-2xl font-bold text-[#4CD964]">
            {@credits_balance} {if @credits_balance == 1, do: "credit", else: "credits"}
          </span>
        </div>

        <%= if @give_credit_success do %>
          <div class="bg-[#E8F8EB] border border-[#4CD964] rounded-xl p-3 mb-4 text-sm text-[#1C1C1E]">
            {@give_credit_success}
          </div>
        <% end %>

        <%!-- Progress toward next credit --%>
        <%= if @credit_progress do %>
          <div class="mb-4">
            <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
              Progress toward next credit
            </p>
            <div class="space-y-3">
              <%!-- Students progress --%>
              <div>
                <div class="flex justify-between text-xs text-[#8E8E93] mb-1">
                  <span>Students</span>
                  <span>{@credit_progress.students.batch_progress}/10</span>
                </div>
                <div class="w-full bg-[#F5F5F7] rounded-full h-2">
                  <div
                    class="bg-[#4CD964] h-2 rounded-full transition-all"
                    style={"width: #{min(100, @credit_progress.students.batch_progress * 10)}%"}
                  >
                  </div>
                </div>
              </div>
              <%!-- Materials progress --%>
              <div>
                <div class="flex justify-between text-xs text-[#8E8E93] mb-1">
                  <span>Materials uploaded</span>
                  <span>{@credit_progress.materials.quarter_units}/4 quarter-units</span>
                </div>
                <div class="w-full bg-[#F5F5F7] rounded-full h-2">
                  <div
                    class="bg-[#4CD964] h-2 rounded-full transition-all"
                    style={"width: #{min(100, @credit_progress.materials.quarter_units * 25)}%"}
                  >
                  </div>
                </div>
              </div>
              <%!-- Tests progress --%>
              <div>
                <div class="flex justify-between text-xs text-[#8E8E93] mb-1">
                  <span>Tests created</span>
                  <span>{@credit_progress.tests.quarter_units}/4 quarter-units</span>
                </div>
                <div class="w-full bg-[#F5F5F7] rounded-full h-2">
                  <div
                    class="bg-[#4CD964] h-2 rounded-full transition-all"
                    style={"width: #{min(100, @credit_progress.tests.quarter_units * 25)}%"}
                  >
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Give a credit --%>
        <div class="border-t border-[#E5E5EA] pt-4 mb-4">
          <button
            class="text-sm font-medium text-[#4CD964] hover:text-[#3DBF55] transition-colors"
            phx-click="toggle_give_credit"
          >
            {if @give_credit_open, do: "Cancel", else: "Give a credit to someone"}
          </button>

          <%= if @give_credit_open do %>
            <div class="mt-3 space-y-3">
              <%= if @give_credit_error do %>
                <p class="text-xs text-[#FF3B30]">{@give_credit_error}</p>
              <% end %>
              <div class="relative">
                <input
                  type="text"
                  value={@give_credit_search}
                  phx-keyup="search_recipients"
                  phx-value-query={@give_credit_search}
                  placeholder="Search by name or email..."
                  class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm transition-colors"
                />
                <%= if @give_credit_results != [] do %>
                  <div class="absolute z-10 w-full bg-white border border-[#E5E5EA] rounded-xl shadow-lg mt-1 py-1">
                    <button
                      :for={r <- @give_credit_results}
                      type="button"
                      class="w-full text-left px-4 py-2 text-sm text-[#1C1C1E] hover:bg-[#F5F5F7] transition-colors"
                      phx-click="select_recipient"
                      phx-value-id={r.id}
                    >
                      {r.display_name || r.email}
                      <span class="text-xs text-[#8E8E93] ml-1">{r.email}</span>
                    </button>
                  </div>
                <% end %>
              </div>

              <%= if @give_credit_recipient do %>
                <p class="text-xs text-[#8E8E93]">
                  Sending to:
                  <strong class="text-[#1C1C1E]">
                    {@give_credit_recipient.display_name || @give_credit_recipient.email}
                  </strong>
                </p>
              <% end %>

              <form phx-submit="give_credit_submit" class="flex gap-2">
                <input
                  type="text"
                  name="note"
                  placeholder="Add a note (optional)"
                  class="flex-1 px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none text-sm transition-colors"
                />
                <button
                  type="submit"
                  disabled={@credits_balance < 1 or is_nil(@give_credit_recipient)}
                  class="bg-[#4CD964] hover:bg-[#3DBF55] disabled:opacity-40 disabled:cursor-not-allowed text-white font-medium px-4 py-2 rounded-full shadow-md transition-colors text-sm"
                >
                  Give 1 credit
                </button>
              </form>
            </div>
          <% end %>
        </div>

        <%!-- Recent activity --%>
        <div>
          <p class="text-xs font-semibold text-[#8E8E93] uppercase tracking-wide mb-3">
            Recent activity
          </p>
          <%= if @credit_ledger == [] do %>
            <p class="text-sm text-[#8E8E93]">
              No activity yet. Earn credits by growing your classroom!
            </p>
          <% else %>
            <ul class="space-y-2">
              <li :for={entry <- @credit_ledger} class="flex items-center justify-between text-sm">
                <span class="text-[#1C1C1E]">{ledger_source_label(entry)}</span>
                <span class={"font-semibold #{if entry.delta > 0, do: "text-[#4CD964]", else: "text-[#FF3B30]"}"}>
                  {if entry.delta > 0, do: "+"}{(div(entry.delta, 4) != 0 &&
                                                   "#{div(entry.delta, 4)} credit") ||
                    "#{rem(abs(entry.delta), 4)}/4 unit"}
                </span>
              </li>
            </ul>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp readiness_badge_colors(score) when score > 70, do: {"text-[#4CD964]", "bg-[#E8F8EB]"}
  defp readiness_badge_colors(score) when score >= 40, do: {"text-[#FF9500]", "bg-[#FFF8E1]"}
  defp readiness_badge_colors(_), do: {"text-[#FF3B30]", "bg-[#FFE5E3]"}

  defp ledger_source_label(%{source: "referral"}), do: "Students joined"
  defp ledger_source_label(%{source: "material_upload"}), do: "Material uploaded"
  defp ledger_source_label(%{source: "test_created"}), do: "Test created"
  defp ledger_source_label(%{source: "transfer_out"}), do: "→ Given to someone"
  defp ledger_source_label(%{source: "transfer_in"}), do: "← Received credit"
  defp ledger_source_label(%{source: "redemption"}), do: "Redeemed for subscription"
  defp ledger_source_label(%{source: "admin_grant"}), do: "Admin grant"
  defp ledger_source_label(_), do: "Credit activity"
end
