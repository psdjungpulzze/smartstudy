defmodule FunSheep.Interactor.AgentRegistry do
  @moduledoc """
  Introspects FunSheep modules implementing `FunSheep.Interactor.AssistantSpec`
  and compares their declared `assistant_attrs/0` against the live Interactor
  configuration so admins can spot drift at a glance.

  A row is "in sync" when the intended model matches the live model (other
  fields are informational only for now — the common drift case is "I
  updated the model in code but the old one is still live").
  """

  alias FunSheep.Interactor.{Agents, AssistantSpec}

  @default_specs [FunSheep.Tutor, FunSheep.Questions.Validation]

  @type row :: %{
          module: module(),
          name: String.t(),
          intended_model: String.t() | nil,
          intended_provider: String.t() | nil,
          intended_attrs: map(),
          live_id: String.t() | nil,
          live_model: String.t() | nil,
          live_attrs: map() | nil,
          status: :in_sync | :drift | :missing | :unreachable
        }

  @doc """
  Returns one registry row per module that implements
  `FunSheep.Interactor.AssistantSpec`. If the Interactor service is
  unreachable, status is `:unreachable` and `:live_*` fields are nil.

  `specs` can be overridden for tests — defaults to `@default_specs`.
  """
  @spec list([module()]) :: [row()]
  def list(specs \\ @default_specs) do
    live_by_name = fetch_live_by_name()

    Enum.map(specs, fn mod ->
      attrs = safe_attrs(mod)
      name = attrs[:name] || attrs["name"]
      intended_model = attrs[:llm_model] || attrs["llm_model"]
      intended_provider = attrs[:llm_provider] || attrs["llm_provider"]

      case live_by_name do
        :unreachable ->
          %{
            module: mod,
            name: name,
            intended_model: intended_model,
            intended_provider: intended_provider,
            intended_attrs: attrs,
            live_id: nil,
            live_model: nil,
            live_attrs: nil,
            status: :unreachable
          }

        %{} = by_name ->
          live = Map.get(by_name, name)
          live_model = extract_model(live)

          %{
            module: mod,
            name: name,
            intended_model: intended_model,
            intended_provider: intended_provider,
            intended_attrs: attrs,
            live_id: live && (live["id"] || live[:id]),
            live_model: live_model,
            live_attrs: live,
            status: classify_status(live, intended_model, live_model)
          }
      end
    end)
  end

  @doc """
  Force re-provisions one module's assistant: DELETEs the live row and
  re-creates it from `assistant_attrs/0`. Returns `{:ok, new_id}` or
  `{:error, reason}`. Interactor's UPDATE endpoint doesn't support model
  changes (per docs), so delete-then-create is the supported flow.
  """
  @spec reprovision(module()) :: {:ok, String.t()} | {:error, term()}
  def reprovision(mod) when is_atom(mod) do
    attrs = safe_attrs(mod)
    name = attrs[:name] || attrs["name"]

    with {:ok, live_by_name} <- fetch_live_by_name_strict(),
         live_row = Map.get(live_by_name, name),
         :ok <- maybe_delete(live_row) do
      case Agents.create_assistant(attrs) do
        {:ok, %{"data" => %{"id" => id}}} ->
          {:ok, id}

        {:ok, %{"id" => id}} ->
          {:ok, id}

        {:ok, %{"data" => data}} when is_map(data) ->
          {:ok, data["id"]}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  Returns the module list used by `list/0`. Tests can override via the
  optional argument on `list/1`.
  """
  def default_specs, do: @default_specs

  @doc """
  Sanity-check that a module implements `AssistantSpec`. Used in tests and
  by the registry itself.
  """
  @spec implements_spec?(module()) :: boolean()
  def implements_spec?(mod) when is_atom(mod) do
    function_exported?(mod, :assistant_attrs, 0) and
      Enum.member?(behaviours(mod), AssistantSpec)
  rescue
    _ -> false
  end

  ## --- Internal --------------------------------------------------------

  defp safe_attrs(mod) do
    Code.ensure_loaded(mod)

    cond do
      function_exported?(mod, :assistant_attrs, 0) ->
        apply(mod, :assistant_attrs, [])

      true ->
        %{}
    end
  end

  defp behaviours(mod) do
    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        attrs = mod.__info__(:attributes)
        Keyword.get_values(attrs, :behaviour) |> List.flatten()

      _ ->
        []
    end
  end

  defp fetch_live_by_name do
    case Agents.list_assistants() do
      {:ok, %{"data" => items}} when is_list(items) ->
        Map.new(items, &{&1["name"], &1})

      {:ok, items} when is_list(items) ->
        Map.new(items, &{&1["name"], &1})

      _ ->
        :unreachable
    end
  end

  defp fetch_live_by_name_strict do
    case fetch_live_by_name() do
      :unreachable -> {:error, :interactor_unreachable}
      other -> {:ok, other}
    end
  end

  defp extract_model(nil), do: nil
  defp extract_model(map) when is_map(map), do: map["llm_model"] || map[:llm_model]

  defp classify_status(nil, _intended, _live), do: :missing
  defp classify_status(_, nil, _), do: :in_sync
  defp classify_status(_, intended, live) when intended == live, do: :in_sync
  defp classify_status(_, _, _), do: :drift

  defp maybe_delete(nil), do: :ok

  defp maybe_delete(%{"id" => id}) when is_binary(id) do
    case Agents.delete_assistant(id) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  defp maybe_delete(_), do: :ok
end
