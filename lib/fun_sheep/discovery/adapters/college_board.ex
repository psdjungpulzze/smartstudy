defmodule FunSheep.Discovery.Adapters.CollegeBoard do
  @moduledoc """
  Direct source adapter for College Board (collegeboard.org).

  The 8 official SAT practice tests are publicly available PDFs from
  College Board's CDN. These are the gold-standard source — each test
  contains ~44 Math questions and ~54 Reading/Writing questions.

  This adapter returns the known stable URLs for:
    - 8 official SAT practice tests (PDFs)
    - AP exam free-response question PDFs (2018–2024 releases)

  No HTTP call needed to enumerate these — the URLs are stable and
  well-documented public resources. The adapter HEAD-probes each URL
  to confirm it is still live before returning it.

  Returns `[%{url:, title:, source_type:, discovery_strategy: "api_adapter",
              publisher: "collegeboard.org", tier: 1}]`.
  """

  require Logger

  @timeout 10_000

  # Official SAT practice test PDFs — publicly listed on collegeboard.org
  # These URLs are stable and version-checked annually.
  @sat_practice_tests [
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-1.pdf",
      title: "Official SAT Practice Test 1",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-2.pdf",
      title: "Official SAT Practice Test 2",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-3.pdf",
      title: "Official SAT Practice Test 3",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-4.pdf",
      title: "Official SAT Practice Test 4",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-5.pdf",
      title: "Official SAT Practice Test 5",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-6.pdf",
      title: "Official SAT Practice Test 6",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-7.pdf",
      title: "Official SAT Practice Test 7",
      source_type: "practice_test"
    },
    %{
      url: "https://satsuite.collegeboard.org/media/pdf/official-sat-practice-test-8.pdf",
      title: "Official SAT Practice Test 8",
      source_type: "practice_test"
    }
  ]

  # AP free-response question PDFs — College Board publishes these annually.
  # Format: https://apcentral.collegeboard.org/media/pdf/ap-{subject}-frq-{year}.pdf
  @ap_subjects %{
    "ap_biology" => "biology",
    "ap_chemistry" => "chemistry",
    "ap_calculus_ab" => "calculus-ab",
    "ap_calculus_bc" => "calculus-bc",
    "ap_physics_1" => "physics-1",
    "ap_physics_2" => "physics-2",
    "ap_statistics" => "statistics",
    "ap_us_history" => "united-states-history",
    "ap_world_history" => "world-history",
    "ap_us_government" => "us-government-and-politics",
    "ap_english_lang" => "english-language-and-composition",
    "ap_english_lit" => "english-literature-and-composition",
    "ap_psychology" => "psychology",
    "ap_economics_micro" => "microeconomics",
    "ap_economics_macro" => "macroeconomics",
    "ap_computer_science_a" => "computer-science-a",
    "ap_environmental_science" => "environmental-science",
    "ap_spanish_lang" => "spanish-language-and-culture"
  }

  @frq_years [2024, 2023, 2022, 2021, 2020]
  @frq_base "https://apcentral.collegeboard.org/media/pdf"

  @doc """
  Returns known College Board source URLs for the given test type and subject.
  Probes each URL and drops any that are no longer reachable.
  """
  @spec discover(String.t() | nil, String.t() | nil, keyword()) :: [map()]
  def discover(test_type, _catalog_subject, opts \\ []) do
    probe_fn = Keyword.get(opts, :probe_fn, &default_probe/1)

    candidates =
      case test_type do
        "sat" ->
          @sat_practice_tests

        t when is_map_key(@ap_subjects, t) ->
          ap_frqs_for(t)

        _ ->
          []
      end

    candidates
    |> Enum.map(fn entry ->
      Map.merge(entry, %{
        publisher: "collegeboard.org",
        discovery_strategy: "api_adapter",
        confidence: 0.99
      })
    end)
    |> probe_alive(probe_fn)
  end

  defp ap_frqs_for(test_type) do
    subject_slug = Map.fetch!(@ap_subjects, test_type)

    Enum.map(@frq_years, fn year ->
      %{
        url: "#{@frq_base}/ap-#{subject_slug}-frq-#{year}.pdf",
        title: "AP #{ap_display_name(subject_slug)} Free Response Questions #{year}",
        source_type: "practice_test"
      }
    end)
  end

  defp probe_alive(candidates, probe_fn) do
    candidates
    |> Task.async_stream(
      fn entry ->
        case probe_fn.(entry.url) do
          :ok -> {:keep, entry}
          {:error, reason} ->
            Logger.debug("[CollegeBoard] URL not reachable #{entry.url}: #{inspect(reason)}")
            :drop
        end
      end,
      max_concurrency: 8,
      timeout: @timeout + 2_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, {:keep, entry}} -> [entry]
      {:ok, :drop} -> []
      {:exit, _} -> []
    end)
  end

  defp ap_display_name(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp default_probe(url) do
    case Req.head(url, receive_timeout: @timeout, max_redirects: 3, retry: false) do
      {:ok, %{status: s}} when s in 200..399 -> :ok
      {:ok, %{status: s}} -> {:error, {:http, s}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :exception}
  end
end
