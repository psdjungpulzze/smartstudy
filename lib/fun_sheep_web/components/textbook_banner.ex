defmodule FunSheepWeb.TextbookBanner do
  @moduledoc """
  UI components that surface the textbook completeness status returned by
  `FunSheep.Courses.textbook_status/1`.

  Two variants:
    * `full_banner/1`   — prominent inline callout with explanation + CTA.
                          Used on the course detail page.
    * `compact_badge/1` — small pill/badge. Used on listing cards where
                          real estate is tight.
  """

  use Phoenix.Component

  import FunSheepWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @type status :: :missing | :processing | :partial | :complete

  attr :status, :map, required: true, doc: "Map returned by Courses.textbook_status/1"
  attr :course_id, :string, required: true
  attr :on_cta, :any, default: nil, doc: "JS command or event name triggered by the CTA button"

  attr :cta_navigate, :string,
    default: nil,
    doc: "If set, CTA becomes a navigate link to this path"

  attr :class, :string, default: ""

  @spec full_banner(map()) :: Phoenix.LiveView.Rendered.t()
  def full_banner(%{status: %{status: :complete}} = assigns) do
    # Don't render anything when the textbook is confirmed complete — no news
    # is good news. Keep the function head so callers don't need conditionals.
    ~H"""
    <div :if={show_complete_pill?(@status)} class={["mb-4", @class]}>
      <div class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#E8F8EB] text-[#3DBF55] text-xs font-medium">
        <.icon name="hero-check-badge" class="w-4 h-4" /> Full textbook attached
      </div>
    </div>
    """
  end

  def full_banner(%{status: %{status: :failed}} = assigns) do
    assigns =
      assigns
      |> assign(:tone, tone(:failed))
      |> assign(:copy, copy(assigns.status))

    ~H"""
    <div class={[
      "mb-4 rounded-2xl border p-4 sm:p-5 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-4",
      @tone.container,
      @class
    ]}>
      <div class={[
        "w-10 h-10 rounded-full flex items-center justify-center shrink-0",
        @tone.icon_wrap
      ]}>
        <.icon name={@tone.icon} class={["w-5 h-5", @tone.icon_color]} />
      </div>
      <div class="flex-1 min-w-0">
        <h3 class={["font-bold text-sm sm:text-base", @tone.title_color]}>{@copy.title}</h3>
        <p class="text-sm text-gray-700 mt-1 leading-relaxed">{@copy.body}</p>
      </div>
      <div class="flex shrink-0 self-stretch sm:self-auto sm:ml-auto">
        <.cta_button
          cta_navigate={@cta_navigate}
          on_cta={@on_cta}
          course_id={@course_id}
          label={@copy.cta}
          tone={@tone}
        />
      </div>
    </div>
    """
  end

  def full_banner(assigns) do
    assigns =
      assigns
      |> assign(:tone, tone(assigns.status.status))
      |> assign(:copy, copy(assigns.status))

    ~H"""
    <div class={[
      "mb-4 rounded-2xl border p-4 sm:p-5 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-4",
      @tone.container,
      @class
    ]}>
      <div class={[
        "w-10 h-10 rounded-full flex items-center justify-center shrink-0",
        @tone.icon_wrap
      ]}>
        <.icon name={@tone.icon} class={["w-5 h-5", @tone.icon_color]} />
      </div>

      <div class="flex-1 min-w-0">
        <h3 class={["font-bold text-sm sm:text-base", @tone.title_color]}>
          {@copy.title}
        </h3>
        <p class="text-sm text-gray-700 mt-1 leading-relaxed">{@copy.body}</p>
        <p
          :if={@status.completeness_score && @status.status == :partial}
          class="text-xs text-gray-500 mt-2"
        >
          Coverage estimate: {coverage_percent(@status.completeness_score)}%
          <span :if={@status.notes}>— {@status.notes}</span>
        </p>
      </div>

      <div class="flex shrink-0 self-stretch sm:self-auto sm:ml-auto">
        <.cta_button
          cta_navigate={@cta_navigate}
          on_cta={@on_cta}
          course_id={@course_id}
          label={@copy.cta}
          tone={@tone}
        />
      </div>
    </div>
    """
  end

  attr :status, :map, required: true
  attr :class, :string, default: ""

  @doc """
  Small pill-shaped indicator suitable for dense list rows. Hidden when the
  textbook is confirmed complete.
  """
  @spec compact_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def compact_badge(%{status: %{status: :complete}} = assigns) do
    ~H"""
    <span class={["hidden", @class]}></span>
    """
  end

  def compact_badge(%{status: %{status: :failed}} = assigns) do
    assigns = assign(assigns, :tone, tone(:failed))

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold",
        @tone.chip,
        @class
      ]}
      title="Processing failed"
    >
      <.icon name="hero-x-circle" class="w-3 h-3" /> Processing failed
    </span>
    """
  end

  def compact_badge(assigns) do
    assigns = assign(assigns, :tone, tone(assigns.status.status))

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] sm:text-xs font-bold",
        @tone.chip,
        @class
      ]}
      title={short_title(@status.status)}
    >
      <.icon name={@tone.icon} class="w-3 h-3" /> {short_title(@status.status)}
    </span>
    """
  end

  # ── CTA button ──────────────────────────────────────────────────────────

  attr :cta_navigate, :string, default: nil
  attr :on_cta, :any, default: nil
  attr :course_id, :string, required: true
  attr :label, :string, required: true
  attr :tone, :map, required: true

  defp cta_button(%{cta_navigate: nav} = assigns) when is_binary(nav) do
    ~H"""
    <.link
      navigate={@cta_navigate}
      class={[
        "inline-flex items-center justify-center gap-2 font-bold px-5 py-2.5 rounded-full shadow-md text-sm touch-target whitespace-nowrap flex-1 sm:flex-none",
        @tone.cta
      ]}
    >
      <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> {@label}
    </.link>
    """
  end

  defp cta_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_cta || JS.push("toggle_upload")}
      class={[
        "inline-flex items-center justify-center gap-2 font-bold px-5 py-2.5 rounded-full shadow-md text-sm touch-target whitespace-nowrap flex-1 sm:flex-none",
        @tone.cta
      ]}
    >
      <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> {@label}
    </button>
    """
  end

  # ── Copy + tone ─────────────────────────────────────────────────────────

  defp copy(%{status: :missing}) do
    %{
      title: "Upload the textbook to power this course",
      body:
        "Every FunSheep course is built from the textbook itself. " <>
          "Upload a PDF or scan of the full textbook so we can generate accurate " <>
          "questions and tests based on your actual source material.",
      cta: "Upload Textbook"
    }
  end

  defp copy(%{status: :failed}) do
    %{
      title: "Textbook processing failed",
      body:
        "We couldn't process your uploaded file. This is usually a temporary issue — " <>
          "try reprocessing, or upload a different copy of the textbook.",
      cta: "Upload Another Copy"
    }
  end

  defp copy(%{status: :processing}) do
    %{
      title: "Textbook is being processed",
      body:
        "We're extracting text from your textbook. Questions will be generated " <>
          "once OCR finishes. Feel free to come back in a few minutes.",
      cta: "Add Another Copy"
    }
  end

  defp copy(%{status: :partial} = s) do
    detail =
      case s.notes do
        nil -> "Some chapters appear to be missing."
        "" -> "Some chapters appear to be missing."
        notes -> notes
      end

    %{
      title: "This textbook looks incomplete",
      body:
        "We couldn't verify that the file covers the whole textbook. " <>
          detail <>
          " Upload a more complete copy so tests reflect the full curriculum.",
      cta: "Upload Full Textbook"
    }
  end

  defp copy(%{status: :complete}),
    do: %{title: "Textbook attached", body: "", cta: "Upload Another"}

  defp tone(:missing) do
    %{
      container: "bg-amber-50 border-amber-200",
      icon_wrap: "bg-amber-100",
      icon: "hero-exclamation-triangle",
      icon_color: "text-amber-600",
      title_color: "text-amber-900",
      chip: "bg-amber-50 text-amber-700",
      cta: "bg-[#4CD964] hover:bg-[#3DBF55] text-white"
    }
  end

  defp tone(:partial) do
    %{
      container: "bg-amber-50 border-amber-200",
      icon_wrap: "bg-amber-100",
      icon: "hero-exclamation-circle",
      icon_color: "text-amber-600",
      title_color: "text-amber-900",
      chip: "bg-amber-50 text-amber-700",
      cta: "bg-[#4CD964] hover:bg-[#3DBF55] text-white"
    }
  end

  defp tone(:failed) do
    %{
      container: "bg-red-50 border-red-200",
      icon_wrap: "bg-red-100",
      icon: "hero-x-circle",
      icon_color: "text-red-600",
      title_color: "text-red-900",
      chip: "bg-red-50 text-red-700",
      cta: "bg-[#4CD964] hover:bg-[#3DBF55] text-white"
    }
  end

  defp tone(:processing) do
    %{
      container: "bg-blue-50 border-blue-200",
      icon_wrap: "bg-blue-100",
      icon: "hero-arrow-path",
      icon_color: "text-blue-600",
      title_color: "text-blue-900",
      chip: "bg-blue-50 text-blue-700",
      cta: "bg-white hover:bg-gray-50 text-gray-700 border border-gray-200"
    }
  end

  defp tone(:complete) do
    %{
      container: "bg-[#E8F8EB] border-[#4CD964]",
      icon_wrap: "bg-[#E8F8EB]",
      icon: "hero-check-badge",
      icon_color: "text-[#3DBF55]",
      title_color: "text-[#1C1C1E]",
      chip: "bg-[#E8F8EB] text-[#3DBF55]",
      cta: "bg-white hover:bg-gray-50 text-gray-700 border border-gray-200"
    }
  end

  defp short_title(:missing), do: "No textbook"
  defp short_title(:failed), do: "Processing failed"
  defp short_title(:partial), do: "Textbook incomplete"
  defp short_title(:processing), do: "Processing"
  defp short_title(:complete), do: "Textbook ready"

  defp coverage_percent(nil), do: "—"
  defp coverage_percent(score) when is_float(score), do: round(score * 100)

  defp show_complete_pill?(_status), do: false
end
