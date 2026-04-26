defmodule FunSheep.Discovery.Metrics do
  @moduledoc """
  Telemetry.Metrics definitions for the web question extraction pipeline.

  Attach these to FunSheepWeb.Telemetry so they are collected alongside
  existing Phoenix/Ecto/Oban metrics.

  Events emitted by the pipeline:

    [:fun_sheep, :discovery, :search_complete]
      measurements: %{results_count: integer}
      metadata:     %{query: string, source_type: string, error?: string}

    [:fun_sheep, :discovery, :url_probe_complete]
      measurements: %{count: 1}
      metadata:     %{url: string, outcome: :keep | :drop, reason: atom}

    [:fun_sheep, :scraper, :source_complete]
      measurements: %{questions_extracted: integer}
      metadata:     %{source_id: uuid, url: string, outcome: :ok | :empty}

    [:fun_sheep, :scraper, :extraction_gate_reject]
      measurements: %{count: 1}
      metadata:     %{reason: atom, source: :ai | :regex}

    [:fun_sheep, :validation, :verdict]
      measurements: %{count: 1, score: float}
      metadata:     %{verdict: atom, source_type: atom}
  """

  import Telemetry.Metrics

  def metrics do
    [
      # --- Discovery: web search ---
      counter("fun_sheep.discovery.search_complete.count",
        description: "Web search queries completed"
      ),
      sum("fun_sheep.discovery.search_complete.results_count",
        description: "Total URLs returned by web searches"
      ),

      # --- Discovery: URL validation ---
      counter("fun_sheep.discovery.url_probe_complete.count",
        tags: [:outcome],
        tag_values: fn meta -> %{outcome: meta.outcome} end,
        description: "URLs probed (keep vs drop)"
      ),

      # --- Scraper: per-source completion ---
      counter("fun_sheep.scraper.source_complete.count",
        tags: [:outcome],
        tag_values: fn meta -> %{outcome: meta.outcome} end,
        description: "Sources scraped, by outcome (:ok | :empty)"
      ),
      sum("fun_sheep.scraper.source_complete.questions_extracted",
        description: "Questions extracted across all sources"
      ),

      # --- Extractor: gate rejections ---
      counter("fun_sheep.scraper.extraction_gate_reject.count",
        tags: [:reason],
        tag_values: fn meta -> %{reason: meta.reason} end,
        description: "Questions rejected by pre-insert gates, by reason"
      ),

      # --- Validation: verdicts ---
      counter("fun_sheep.validation.verdict.count",
        tags: [:verdict, :source_type],
        tag_values: fn meta -> %{verdict: meta.verdict, source_type: meta.source_type} end,
        description: "Validation verdicts applied, by verdict and source type"
      ),
      last_value("fun_sheep.validation.verdict.score",
        tags: [:source_type],
        tag_values: fn meta -> %{source_type: meta.source_type} end,
        description: "Most recent validation score by source type"
      )
    ]
  end
end
