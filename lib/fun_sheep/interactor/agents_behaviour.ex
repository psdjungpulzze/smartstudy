defmodule FunSheep.Interactor.AgentsBehaviour do
  @moduledoc """
  Callbacks the workers use when talking to `FunSheep.Interactor.Agents`.

  Exists so background workers can swap the implementation under test via
  `Application.get_env(:fun_sheep, :interactor_agents_impl, FunSheep.Interactor.Agents)`.
  Production always runs the real module; tests route through a Mox-backed
  stub defined in `test/support/mocks.ex`.

  Only the call sites the workers actually need are surfaced here — the wider
  `FunSheep.Interactor.Agents` module keeps its direct API for other callers.
  """

  @callback chat(assistant_name :: String.t(), prompt :: String.t(), opts :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @callback resolve_or_create_assistant(attrs :: map()) ::
              {:ok, String.t()} | {:error, term()}
end
