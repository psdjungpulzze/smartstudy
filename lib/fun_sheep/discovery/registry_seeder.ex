defmodule FunSheep.Discovery.RegistrySeeder do
  @moduledoc """
  Seeds `DiscoveredSource` records from the curated `source_registry_entries` table.

  Called by `WebContentDiscoveryWorker` before the web search pass so that every
  course gets the best-known sources immediately, without waiting for web search.

  Registry entries are matched on `(test_type, catalog_subject)`:
    - A nil `catalog_subject` entry matches ALL subjects for a given test_type.
    - An explicit `catalog_subject` entry overrides the nil entry for that subject.

  Created `DiscoveredSource` records use `discovery_strategy: "registry"` and are
  inserted with `create_discovered_source_if_new` to remain idempotent (re-seeding
  a course that already has these sources is a no-op).
  """

  import Ecto.Query

  alias FunSheep.{Content, Repo}
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Discovery.SourceRegistryEntry

  require Logger

  @doc """
  Seeds discovered sources for `course` from matching registry entries.

  Returns `{:ok, count}` where `count` is the number of new sources inserted
  (0 if all were already present or no entries matched).
  """
  @spec seed_from_registry(map()) :: {:ok, non_neg_integer()}
  def seed_from_registry(%{id: course_id, catalog_test_type: test_type, catalog_subject: subject}) do
    entries = fetch_entries(test_type, subject)

    if entries == [] do
      Logger.info("[RegistrySeeder] No registry entries for test_type=#{test_type} subject=#{subject || "any"}")
      {:ok, 0}
    else
      Logger.info("[RegistrySeeder] Seeding #{length(entries)} registry entries for course #{course_id}")

      inserted =
        entries
        |> Enum.reduce(0, fn entry, acc ->
          case insert_source(course_id, entry) do
            :inserted -> acc + 1
            :existing -> acc
            :error -> acc
          end
        end)

      Logger.info("[RegistrySeeder] Inserted #{inserted} new sources for course #{course_id}")
      {:ok, inserted}
    end
  end

  @doc """
  Returns all enabled registry entries matching a `(test_type, catalog_subject)` pair.

  Nil-subject entries (wildcard) are always included alongside subject-specific ones.
  Results are ordered tier ASC (best sources first).
  """
  @spec entries_for(String.t(), String.t() | nil) :: [SourceRegistryEntry.t()]
  def entries_for(test_type, catalog_subject \\ nil) do
    fetch_entries(test_type, catalog_subject)
  end

  # --- Private helpers ---

  defp fetch_entries(test_type, nil) do
    from(e in SourceRegistryEntry,
      where: e.test_type == ^test_type and e.is_enabled == true and is_nil(e.catalog_subject),
      order_by: [asc: e.tier]
    )
    |> Repo.all()
  end

  defp fetch_entries(test_type, subject) do
    from(e in SourceRegistryEntry,
      where:
        e.test_type == ^test_type and
          e.is_enabled == true and
          (is_nil(e.catalog_subject) or e.catalog_subject == ^subject),
      order_by: [asc: e.tier]
    )
    |> Repo.all()
  end

  defp insert_source(course_id, %SourceRegistryEntry{} = entry) do
    if Repo.get_by(DiscoveredSource, course_id: course_id, url: entry.url_or_pattern) do
      :existing
    else
      attrs = %{
        course_id: course_id,
        url: entry.url_or_pattern,
        title: title_for(entry),
        source_type: entry.source_type,
        discovery_strategy: "registry",
        status: "discovered"
      }

      case Content.create_discovered_source_if_new(attrs) do
        {:ok, _} ->
          :inserted

        {:error, changeset} ->
          Logger.warning(
            "[RegistrySeeder] Failed to insert #{entry.url_or_pattern}: #{inspect(changeset.errors)}"
          )
          :error
      end
    end
  end

  defp title_for(%SourceRegistryEntry{source_type: type, domain: domain}) do
    label =
      case type do
        "official" -> "Official resource"
        "question_bank" -> "Question bank"
        "practice_test" -> "Practice test"
        "study_guide" -> "Study guide"
        _ -> "Resource"
      end

    "#{label} — #{domain}"
  end
end
