defmodule FunSheep.Questions.Deduplicator do
  @moduledoc """
  Content-fingerprint deduplication for web-scraped questions.

  Fingerprint = first 16 hex characters of SHA-256(normalize(content)).
  Normalization strips punctuation, whitespace, and case so minor
  differences in whitespace or formatting don't create duplicate entries.

  The unique index `questions_course_id_content_fingerprint_index`
  (partial: `source_type = 'web_scraped'`) enforces uniqueness at the DB
  level. The fingerprint is computed here and included in the insert attrs
  so that `Repo.insert(on_conflict: :nothing)` silently skips duplicates.
  """

  @doc """
  Returns a 16-character hex fingerprint for the given question content.
  Deterministic: same logical content always produces the same fingerprint.
  """
  @spec fingerprint(String.t()) :: String.t()
  def fingerprint(content) when is_binary(content) do
    content
    |> normalize()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  def fingerprint(_), do: nil

  # Remove case, punctuation, and extra whitespace so "Which of the following?"
  # and "which of the following" get the same fingerprint.
  defp normalize(content) do
    content
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
