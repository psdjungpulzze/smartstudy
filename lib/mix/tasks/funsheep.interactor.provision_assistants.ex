defmodule Mix.Tasks.Funsheep.Interactor.ProvisionAssistants do
  @shortdoc "Provision every AssistantSpec-backed Interactor assistant"

  @moduledoc """
  Provisions every assistant declared via `FunSheep.Interactor.AssistantSpec`
  on the configured Interactor server.

  Walks the modules of the `:fun_sheep` application, selects those implementing
  the behaviour, and calls `FunSheep.Interactor.Agents.resolve_or_create_assistant/1`
  for each. Idempotent: existing assistants resolve to their current id and
  are left alone; missing ones are created.

  Intended as a pre-deploy step so `scripts/deploy/verify-interactor.sh` finds
  every required assistant — in particular after a rename like
  `question_validator_v2` → `question_quality_reviewer`, where the new name
  has never been seen by Interactor before.

  ## Usage

      mix funsheep.interactor.provision_assistants

  Exits non-zero if any provisioning call fails, so the task can be chained
  from shell scripts via `mix funsheep.interactor.provision_assistants && …`.
  """

  use Mix.Task

  alias FunSheep.Interactor.Agents
  alias FunSheep.Interactor.AssistantSpec

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    specs = discover_specs()

    if specs == [] do
      Mix.shell().info("No AssistantSpec implementations found — nothing to provision.")
      :ok
    else
      Mix.shell().info("Provisioning #{length(specs)} assistant(s)...")

      results = Enum.map(specs, &provision/1)
      failures = Enum.filter(results, &match?({_mod, {:error, _}}, &1))

      if failures == [] do
        Mix.shell().info("All assistants provisioned.")
      else
        Mix.raise("#{length(failures)} assistant(s) failed to provision (see errors above)")
      end
    end
  end

  # Use the :fun_sheep application's module list as the search scope rather
  # than :code.all_loaded/0 — not all beam files are necessarily loaded at
  # task-start time, and scoping to our app avoids matching framework modules
  # that happen to share the behaviour.
  defp discover_specs do
    {:ok, modules} = :application.get_key(:fun_sheep, :modules)

    modules
    |> Enum.filter(&implements_spec?/1)
    |> Enum.sort()
  end

  defp implements_spec?(mod) do
    Code.ensure_loaded?(mod) and
      function_exported?(mod, :assistant_attrs, 0) and
      AssistantSpec in behaviours(mod)
  end

  # `@behaviour` declarations accumulate as repeated `:behaviour` attribute
  # entries; `Keyword.get_values/2` handles the case of multiple behaviours
  # declared on the same module.
  defp behaviours(mod) do
    mod.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp provision(mod) do
    attrs = mod.assistant_attrs()
    name = Map.fetch!(attrs, :name)

    case Agents.resolve_or_create_assistant(attrs) do
      {:ok, id} ->
        Mix.shell().info("  [ok]   #{name} → #{id}")
        {mod, {:ok, id}}

      {:error, reason} = err ->
        Mix.shell().error("  [fail] #{name} (#{inspect(mod)}): #{inspect(reason)}")
        {mod, err}
    end
  end
end
