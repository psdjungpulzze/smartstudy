defmodule FunSheep.FeatureFlags do
  @moduledoc """
  Thin wrapper over `:fun_with_flags` for kill switches.

  Every flag this project cares about lives in `@flags` below — workers
  call `enabled?/1`, admins toggle via `/admin/flags`, and toggling writes
  through Postgres LISTEN/NOTIFY so cluster-wide effect is < 1s.

  Flags default to *enabled*. A flag row only appears in
  `fun_with_flags_toggles` after an admin explicitly disables it; before
  that, `enabled?/1` returns true via the default gate below.
  """

  require Logger

  @flags [
    %{
      name: :ai_question_generation_enabled,
      description:
        "Kill switch for the AIQuestionGenerationWorker. When off, courses still process but question generation is skipped."
    },
    %{
      name: :ocr_enabled,
      description: "Kill switch for OCRMaterialWorker. When off, uploads queue but don't process."
    },
    %{
      name: :interactor_calls_enabled,
      description:
        "Global Interactor circuit breaker — disables every worker that calls Interactor."
    },
    %{
      name: :course_creation_enabled,
      description: "Block new course creation during incidents. Existing courses are unaffected."
    },
    %{
      name: :signup_enabled,
      description:
        "Close registration without taking the site down. Existing users can still log in."
    },
    %{
      name: :maintenance_mode,
      description:
        "When on, the MaintenanceMode plug (Phase 4.3) returns 503 for all non-admin routes."
    }
  ]

  @doc "List every well-known flag as `%{name, description, enabled?}`."
  @spec list() :: [map()]
  def list do
    Enum.map(@flags, fn f ->
      Map.put(f, :enabled?, enabled?(f.name))
    end)
  end

  @doc "Metadata for one flag (or `nil` if unknown)."
  @spec fetch(atom()) :: map() | nil
  def fetch(name) when is_atom(name) do
    Enum.find(@flags, &(&1.name == name))
  end

  @doc """
  True when the flag is on. Unknown flags default to `true` — the plan
  rule is "flags default enabled", so adding a new call-site that isn't
  yet toggleable is safe.
  """
  @spec enabled?(atom()) :: boolean()
  def enabled?(name) when is_atom(name) do
    case FunWithFlags.enabled?(name) do
      true -> true
      false -> false
    end
  rescue
    e ->
      Logger.warning("[FeatureFlags] enabled?(#{name}) crashed: #{Exception.message(e)}")
      true
  end

  @doc "Convenience for worker code: returns `:ok` or `{:cancel, reason}`."
  @spec require!(atom()) :: :ok | {:cancel, String.t()}
  def require!(name) when is_atom(name) do
    if enabled?(name) do
      :ok
    else
      {:cancel, "feature_flag_disabled:#{name}"}
    end
  end

  @doc "Turns a flag ON."
  @spec enable(atom()) :: {:ok, true} | {:error, term()}
  def enable(name) when is_atom(name) do
    case FunWithFlags.enable(name) do
      {:ok, true} = ok -> ok
      {:ok, false} -> {:ok, true}
      err -> err
    end
  end

  @doc "Turns a flag OFF."
  @spec disable(atom()) :: {:ok, false} | {:error, term()}
  def disable(name) when is_atom(name) do
    case FunWithFlags.disable(name) do
      {:ok, false} = ok -> ok
      {:ok, true} -> {:ok, false}
      err -> err
    end
  end

  @doc "Toggles a flag."
  @spec toggle(atom()) :: {:ok, boolean()} | {:error, term()}
  def toggle(name) when is_atom(name) do
    if enabled?(name), do: disable(name), else: enable(name)
  end

  @doc "List of declared flag names (not the current DB state)."
  @spec known_names() :: [atom()]
  def known_names, do: Enum.map(@flags, & &1.name)
end
