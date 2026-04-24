defmodule FunSheep.Geo do
  @moduledoc """
  The Geo context.

  Manages the geographic hierarchy: countries, states, districts, and schools.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Geo.{Country, State, District, School}

  ## Countries

  def list_countries do
    Repo.all(Country)
  end

  def get_country!(id), do: Repo.get!(Country, id)

  def create_country(attrs \\ %{}) do
    %Country{}
    |> Country.changeset(attrs)
    |> Repo.insert()
  end

  def update_country(%Country{} = country, attrs) do
    country
    |> Country.changeset(attrs)
    |> Repo.update()
  end

  def delete_country(%Country{} = country) do
    Repo.delete(country)
  end

  def change_country(%Country{} = country, attrs \\ %{}) do
    Country.changeset(country, attrs)
  end

  ## States

  def list_states do
    Repo.all(State)
  end

  def list_states_by_country(country_id) do
    from(s in State, where: s.country_id == ^country_id, order_by: s.name)
    |> Repo.all()
  end

  def get_state!(id), do: Repo.get!(State, id)

  def get_state(id), do: Repo.get(State, id)

  def create_state(attrs \\ %{}) do
    %State{}
    |> State.changeset(attrs)
    |> Repo.insert()
  end

  def update_state(%State{} = state, attrs) do
    state
    |> State.changeset(attrs)
    |> Repo.update()
  end

  def delete_state(%State{} = state) do
    Repo.delete(state)
  end

  def change_state(%State{} = state, attrs \\ %{}) do
    State.changeset(state, attrs)
  end

  ## Districts

  def list_districts do
    Repo.all(District)
  end

  def list_districts_by_state(state_id) do
    from(d in District, where: d.state_id == ^state_id, order_by: d.name)
    |> Repo.all()
  end

  def get_district!(id), do: Repo.get!(District, id)

  def get_district(id), do: Repo.get(District, id)

  def create_district(attrs \\ %{}) do
    %District{}
    |> District.changeset(attrs)
    |> Repo.insert()
  end

  def update_district(%District{} = district, attrs) do
    district
    |> District.changeset(attrs)
    |> Repo.update()
  end

  def delete_district(%District{} = district) do
    Repo.delete(district)
  end

  def change_district(%District{} = district, attrs \\ %{}) do
    District.changeset(district, attrs)
  end

  ## Schools

  def list_schools do
    Repo.all(School)
  end

  def list_schools_by_district(district_id) do
    from(s in School, where: s.district_id == ^district_id, order_by: s.name)
    |> Repo.all()
  end

  def get_school!(id), do: Repo.get!(School, id)

  def get_school(id), do: Repo.get(School, id)

  def create_school(attrs \\ %{}) do
    %School{}
    |> School.changeset(attrs)
    |> Repo.insert()
  end

  def update_school(%School{} = school, attrs) do
    school
    |> School.changeset(attrs)
    |> Repo.update()
  end

  def delete_school(%School{} = school) do
    Repo.delete(school)
  end

  def change_school(%School{} = school, attrs \\ %{}) do
    School.changeset(school, attrs)
  end

  @doc """
  Search schools by a plain string query (convenience wrapper for onboarding).

  Returns an empty list for queries shorter than 2 characters.
  """
  @spec search_schools(binary(), keyword()) :: [School.t()]
  def search_schools(query, opts) when is_binary(query) and byte_size(query) >= 2 do
    search_schools(Keyword.merge([query: query], opts))
  end

  def search_schools(query, _opts) when is_binary(query), do: []

  @doc """
  Search schools for the profile-setup autocomplete.

  Filters by optional `state_id`/`country_id`, case-insensitive `query`
  against `name` and `native_name`, and optional `level`/`type`. Results
  are capped at `limit` (default 20) and ordered by student_count desc,
  then name — so large/well-known schools surface first.

  Used to replace cascading district + school dropdowns when the DB
  holds 100K+ ingested schools.
  """
  @spec search_schools(map() | keyword()) :: [School.t()]
  def search_schools(opts) do
    opts = Enum.into(opts, %{})
    limit = Map.get(opts, :limit, 20)
    query = Map.get(opts, :query) |> normalize_query()

    base = from(s in School, limit: ^limit)

    base
    |> maybe_filter(:state_id, Map.get(opts, :state_id))
    |> maybe_filter(:country_id, Map.get(opts, :country_id))
    |> maybe_filter(:level, Map.get(opts, :level))
    |> maybe_filter(:type, Map.get(opts, :type))
    |> maybe_filter_name(query)
    |> order_by([s], [fragment("COALESCE(?, 0) DESC", s.student_count), s.name])
    |> Repo.all()
  end

  defp normalize_query(nil), do: nil
  defp normalize_query(""), do: nil

  defp normalize_query(q) when is_binary(q) do
    case String.trim(q) do
      "" -> nil
      t -> t
    end
  end

  defp maybe_filter(query, _k, nil), do: query
  defp maybe_filter(query, _k, ""), do: query
  defp maybe_filter(query, :state_id, v), do: where(query, [s], s.state_id == ^v)
  defp maybe_filter(query, :country_id, v), do: where(query, [s], s.country_id == ^v)
  defp maybe_filter(query, :level, v), do: where(query, [s], s.level == ^v)
  defp maybe_filter(query, :type, v), do: where(query, [s], s.type == ^v)

  defp maybe_filter_name(query, nil), do: query

  defp maybe_filter_name(query, q) do
    pattern = "%" <> q <> "%"

    where(
      query,
      [s],
      ilike(s.name, ^pattern) or ilike(coalesce(s.native_name, ^""), ^pattern)
    )
  end
end
