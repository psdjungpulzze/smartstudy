defmodule FunSheep.Integrations.Registry do
  @moduledoc """
  Maps provider atoms to their adapter modules.

  Adapter module resolution is overridable per-test via application env
  (`config :fun_sheep, :integrations_provider_modules`), which lets the
  sync worker use a Mox double in unit tests while dev/prod use the real
  provider module.
  """

  alias FunSheep.Integrations.Providers.{GoogleClassroom, Canvas, ParentSquare}

  @defaults %{
    google_classroom: GoogleClassroom,
    canvas: Canvas,
    parentsquare: ParentSquare
  }

  @doc "Returns the adapter module for the given provider atom."
  @spec module_for(atom()) :: module()
  def module_for(provider) when is_atom(provider) do
    overrides = Application.get_env(:fun_sheep, :integrations_provider_modules, %{})
    Map.get(overrides, provider) || Map.fetch!(@defaults, provider)
  end

  @doc "List of {provider_atom, module} for every registered provider."
  @spec all() :: [{atom(), module()}]
  def all do
    Enum.map(@defaults, fn {provider, _mod} -> {provider, module_for(provider)} end)
  end

  @doc "Human-readable label for a provider atom."
  @spec label(atom()) :: String.t()
  def label(:google_classroom), do: "Google Classroom"
  def label(:canvas), do: "Canvas LMS"
  def label(:parentsquare), do: "ParentSquare"
end
