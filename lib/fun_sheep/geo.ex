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
end
