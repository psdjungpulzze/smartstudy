defmodule FunSheepWeb.QuestionBankLive do
  use FunSheepWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias FunSheep.Courses
  alias FunSheep.Questions
  alias FunSheep.Questions.Question

  @impl true
  def mount(%{"course_id" => course_id}, _session, socket) do
    course = Courses.get_course_with_chapters!(course_id)
    questions = Questions.list_questions_by_course(course_id)

    {:ok,
     socket
     |> assign(
       page_title: "Question Bank - #{course.name}",
       course: course,
       questions: questions,
       filter_chapter_id: "",
       filter_section_id: "",
       filter_difficulty: "",
       filter_question_type: "",
       show_form: false,
       question_form: nil,
       sections_for_filter: []
     )
     |> allow_upload(:question_figure,
       accept: ~w(.png .jpg .jpeg .webp),
       max_entries: 3,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("filter", params, socket) do
    course_id = socket.assigns.course.id

    filters = %{
      "chapter_id" => params["chapter_id"] || "",
      "section_id" => params["section_id"] || "",
      "difficulty" => params["difficulty"] || "",
      "question_type" => params["question_type"] || ""
    }

    questions = Questions.list_questions_by_course(course_id, filters)

    sections_for_filter =
      if filters["chapter_id"] != "" do
        Courses.list_sections_by_chapter(filters["chapter_id"])
      else
        []
      end

    {:noreply,
     assign(socket,
       questions: questions,
       filter_chapter_id: filters["chapter_id"],
       filter_section_id: filters["section_id"],
       filter_difficulty: filters["difficulty"],
       filter_question_type: filters["question_type"],
       sections_for_filter: sections_for_filter
     )}
  end

  def handle_event("show_add_question", _params, socket) do
    changeset = Questions.change_question(%Question{})

    {:noreply,
     assign(socket,
       show_form: true,
       question_form: to_form(changeset)
     )}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, question_form: nil)}
  end

  def handle_event("validate_question", %{"question" => params}, socket) do
    changeset =
      %Question{}
      |> Questions.change_question(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, question_form: to_form(changeset))}
  end

  def handle_event("save_question", %{"question" => params}, socket) do
    course = socket.assigns.course

    attrs = Map.put(params, "course_id", course.id)

    case Questions.create_question(attrs) do
      {:ok, question} ->
        attach_uploaded_figures(socket, question)

        questions = Questions.list_questions_by_course(course.id)

        {:noreply,
         socket
         |> assign(questions: questions, show_form: false, question_form: nil)
         |> put_flash(:info, "Question added")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, question_form: to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :question_figure, ref)}
  end

  def handle_event("delete_question", %{"id" => question_id}, socket) do
    question = Questions.get_question!(question_id)

    case Questions.delete_question(question) do
      {:ok, _} ->
        questions = Questions.list_questions_by_course(socket.assigns.course.id)

        {:noreply,
         socket
         |> assign(questions: questions)
         |> put_flash(:info, "Question deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete question")}
    end
  end

  # Consumes uploaded figure entries, stores them, creates user-figure
  # SourceFigure records, and links them to the question. Silent no-op when
  # no uploads — the form works fine without figures.
  defp attach_uploaded_figures(socket, question) do
    figure_ids =
      consume_uploaded_entries(socket, :question_figure, fn %{path: path}, entry ->
        with {:ok, binary} <- File.read(path),
             key <-
               Path.join([
                 "user-figures",
                 question.course_id,
                 "#{question.id}-#{entry.uuid}#{Path.extname(entry.client_name)}"
               ]),
             {:ok, stored_key} <-
               FunSheep.Storage.put(key, binary, content_type: entry.client_type) do
          figure_id = create_user_figure(socket, question, stored_key, entry.client_name)
          {:ok, figure_id}
        else
          _ -> {:postpone, :error}
        end
      end)
      |> Enum.reject(&(&1 in [nil, :error]))

    if figure_ids != [] do
      Questions.attach_figures(question, figure_ids)
    end
  end

  # User-uploaded figures live on a synthetic OCR page (page_number=0) so they
  # still fit the same SourceFigure schema used by extracted figures.
  defp create_user_figure(socket, question, stored_key, client_name) do
    alias FunSheep.Content

    case find_or_create_user_figure_page(socket, question) do
      {:ok, page} ->
        {:ok, figure} =
          Content.create_source_figure(%{
            ocr_page_id: page.id,
            material_id: page.material_id,
            page_number: 0,
            figure_type: :image,
            caption: client_name,
            image_path: stored_key
          })

        figure.id

      _ ->
        nil
    end
  end

  defp find_or_create_user_figure_page(socket, question) do
    alias FunSheep.Content

    # Ensure a per-course "user-uploads" material/page exists so figures FK
    # cleanly. Cheap fan-out: one row per course.
    material = ensure_user_uploads_material(socket, question.course_id)

    existing =
      FunSheep.Repo.get_by(Content.OcrPage, material_id: material.id, page_number: 0)

    case existing do
      %Content.OcrPage{} = page ->
        {:ok, page}

      nil ->
        Content.create_ocr_page(%{
          material_id: material.id,
          page_number: 0,
          status: :completed,
          extracted_text: "User-uploaded figures"
        })
    end
  end

  defp ensure_user_uploads_material(socket, course_id) do
    alias FunSheep.Content.UploadedMaterial

    existing =
      FunSheep.Repo.one(
        from(m in UploadedMaterial,
          where: m.course_id == ^course_id and m.file_name == "__user_figures__"
        )
      )

    case existing do
      %UploadedMaterial{} = m ->
        m

      nil ->
        user_role_id = uploader_role_id(socket, course_id)

        {:ok, m} =
          %UploadedMaterial{}
          |> UploadedMaterial.changeset(%{
            file_path: "virtual/user_figures/#{course_id}",
            file_name: "__user_figures__",
            file_type: "virtual/user-figures",
            file_size: 0,
            user_role_id: user_role_id,
            course_id: course_id,
            ocr_status: :completed
          })
          |> FunSheep.Repo.insert()

        m
    end
  end

  defp uploader_role_id(socket, course_id) do
    # Prefer the signed-in user's role. Fall back to any existing uploader
    # of the course if the socket has no current_user (e.g. tests).
    case get_in(socket.assigns, [:current_user, "user_role_id"]) do
      id when is_binary(id) ->
        id

      _ ->
        from(m in FunSheep.Content.UploadedMaterial,
          where: m.course_id == ^course_id and not is_nil(m.user_role_id),
          select: m.user_role_id,
          limit: 1
        )
        |> FunSheep.Repo.one()
    end
  end

  defp type_label(:multiple_choice), do: "Multiple Choice"
  defp type_label(:short_answer), do: "Short Answer"
  defp type_label(:free_response), do: "Free Response"
  defp type_label(:true_false), do: "True/False"
  defp type_label(_), do: "Unknown"

  defp difficulty_color(:easy), do: "bg-green-50 text-green-700"
  defp difficulty_color(:medium), do: "bg-yellow-50 text-yellow-700"
  defp difficulty_color(:hard), do: "bg-red-50 text-red-700"
  defp difficulty_color(_), do: "bg-gray-100 text-gray-600"

  defp type_color(:multiple_choice), do: "bg-blue-50 text-blue-600"
  defp type_color(:true_false), do: "bg-purple-50 text-purple-600"
  defp type_color(:short_answer), do: "bg-orange-50 text-orange-600"
  defp type_color(:free_response), do: "bg-teal-50 text-teal-600"
  defp type_color(_), do: "bg-gray-100 text-gray-600"

  defp upload_error_message(:too_large), do: "File too large — max 5MB"
  defp upload_error_message(:too_many_files), do: "Too many files — max 3"
  defp upload_error_message(:not_accepted), do: "File type not supported"
  defp upload_error_message(err), do: "Upload error: #{inspect(err)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Breadcrumb --%>
      <div class="mb-6">
        <.link
          navigate={~p"/courses/#{@course.id}"}
          class="text-[#8E8E93] hover:text-[#1C1C1E] text-sm inline-flex items-center transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back to {@course.name}
        </.link>
      </div>

      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-[#1C1C1E]">Question Bank</h1>
          <p class="text-[#8E8E93] mt-1">{@course.name} - {length(@questions)} question(s)</p>
        </div>
        <button
          phx-click="show_add_question"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Add Question
        </button>
      </div>

      <%!-- Filters --%>
      <div class="bg-white rounded-2xl shadow-md p-4 mb-6">
        <form phx-change="filter" class="grid grid-cols-1 md:grid-cols-4 gap-3">
          <select
            name="chapter_id"
            class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
          >
            <option value="">All Chapters</option>
            <%= for ch <- @course.chapters do %>
              <option value={ch.id} selected={@filter_chapter_id == ch.id}>{ch.name}</option>
            <% end %>
          </select>
          <select
            name="section_id"
            class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
          >
            <option value="">All Sections</option>
            <%= for s <- @sections_for_filter do %>
              <option value={s.id} selected={@filter_section_id == s.id}>{s.name}</option>
            <% end %>
          </select>
          <select
            name="difficulty"
            class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
          >
            <option value="">All Difficulties</option>
            <option value="easy" selected={@filter_difficulty == "easy"}>Easy</option>
            <option value="medium" selected={@filter_difficulty == "medium"}>Medium</option>
            <option value="hard" selected={@filter_difficulty == "hard"}>Hard</option>
          </select>
          <select
            name="question_type"
            class="w-full px-4 py-2 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-full outline-none transition-colors text-sm"
          >
            <option value="">All Types</option>
            <option value="multiple_choice" selected={@filter_question_type == "multiple_choice"}>
              Multiple Choice
            </option>
            <option value="short_answer" selected={@filter_question_type == "short_answer"}>
              Short Answer
            </option>
            <option value="free_response" selected={@filter_question_type == "free_response"}>
              Free Response
            </option>
            <option value="true_false" selected={@filter_question_type == "true_false"}>
              True/False
            </option>
          </select>
        </form>
      </div>

      <%!-- Add question form modal --%>
      <div :if={@show_form} class="bg-white rounded-2xl shadow-md p-6 mb-6">
        <h3 class="text-lg font-semibold text-[#1C1C1E] mb-4">Add Question</h3>
        <.form
          for={@question_form}
          phx-change="validate_question"
          phx-submit="save_question"
          class="space-y-4"
        >
          <.input field={@question_form[:content]} type="textarea" label="Question Content" required />
          <.input field={@question_form[:answer]} type="text" label="Answer" required />

          <div>
            <label class="block text-sm font-medium text-[#1C1C1E] mb-2">
              Figures (optional) — up to 3 images
            </label>
            <div
              phx-drop-target={@uploads.question_figure.ref}
              class="border-2 border-dashed border-[#E5E5EA] rounded-2xl p-4 text-center"
            >
              <.live_file_input upload={@uploads.question_figure} class="text-sm" />
              <p class="text-xs text-[#8E8E93] mt-2">
                PNG, JPG, WebP up to 5MB each. Attach when the question needs a table, diagram, or image.
              </p>
            </div>

            <div :for={entry <- @uploads.question_figure.entries} class="mt-2 flex items-center gap-3">
              <.live_img_preview entry={entry} class="w-16 h-16 object-cover rounded-lg" />
              <div class="flex-1 text-sm">
                <p class="text-[#1C1C1E]">{entry.client_name}</p>
                <p class="text-xs text-[#8E8E93]">{entry.progress}%</p>
              </div>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-sm text-[#FF3B30]"
              >
                Remove
              </button>
            </div>

            <p
              :for={err <- upload_errors(@uploads.question_figure)}
              class="text-sm text-[#FF3B30] mt-1"
            >
              {upload_error_message(err)}
            </p>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@question_form[:question_type]}
              type="select"
              label="Question Type"
              prompt="Select type..."
              options={[
                {"Multiple Choice", :multiple_choice},
                {"Short Answer", :short_answer},
                {"Free Response", :free_response},
                {"True/False", :true_false}
              ]}
              required
            />
            <.input
              field={@question_form[:difficulty]}
              type="select"
              label="Difficulty"
              prompt="Select difficulty..."
              options={[{"Easy", :easy}, {"Medium", :medium}, {"Hard", :hard}]}
            />
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@question_form[:chapter_id]}
              type="select"
              label="Chapter (optional)"
              prompt="Select chapter..."
              options={Enum.map(@course.chapters, &{&1.name, &1.id})}
            />
            <.input
              field={@question_form[:section_id]}
              type="select"
              label="Section (optional)"
              prompt="Select section..."
              options={
                @course.chapters
                |> Enum.flat_map(fn ch ->
                  Enum.map(ch.sections, &{"#{ch.name} > #{&1.name}", &1.id})
                end)
              }
            />
          </div>
          <div class="flex gap-3 pt-2">
            <button
              type="submit"
              class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
            >
              Save Question
            </button>
            <button
              type="button"
              phx-click="cancel_form"
              class="bg-white hover:bg-gray-50 text-gray-700 font-medium px-6 py-2 rounded-full border border-gray-200 shadow-sm transition-colors"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>

      <%!-- Questions list --%>
      <div :if={@questions == []} class="bg-white rounded-2xl shadow-md p-8 text-center">
        <.icon name="hero-question-mark-circle" class="w-12 h-12 text-[#8E8E93] mx-auto mb-3" />
        <h3 class="text-lg font-semibold text-[#1C1C1E] mb-2">No questions yet</h3>
        <p class="text-[#8E8E93]">Add your first question to build the question bank.</p>
      </div>

      <div class="space-y-3">
        <div :for={question <- @questions} class="bg-white rounded-2xl shadow-md p-4">
          <div class="flex items-start justify-between">
            <div class="flex-1 mr-4">
              <p class="text-[#1C1C1E] font-medium">{truncate(question.content, 200)}</p>
              <div class="flex flex-wrap gap-2 mt-2">
                <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{type_color(question.question_type)}"}>
                  {type_label(question.question_type)}
                </span>
                <span
                  :if={question.difficulty}
                  class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{difficulty_color(question.difficulty)}"}
                >
                  {question.difficulty |> to_string() |> String.capitalize()}
                </span>
                <span
                  :if={question.chapter}
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
                >
                  {question.chapter.name}
                </span>
                <span
                  :if={question.section}
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
                >
                  {question.section.name}
                </span>
                <span
                  :if={question.is_generated}
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-50 text-purple-600"
                >
                  AI Generated
                </span>
              </div>
            </div>
            <button
              phx-click="delete_question"
              phx-value-id={question.id}
              data-confirm="Delete this question?"
              class="p-1 text-[#8E8E93] hover:text-[#FF3B30] transition-colors"
              aria-label="Delete question"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp truncate(nil, _), do: ""
end
