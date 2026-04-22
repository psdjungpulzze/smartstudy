defmodule FunSheep.Test.Mocks do
  @moduledoc """
  Documentation placeholder for Mox-backed test doubles.

  Mocks themselves are registered via `Mox.defmock/2` in `test/test_helper.exs`
  so the mock modules exist before any test starts. When adding a new mock:

    1. Define the behaviour in `lib/` (e.g. `FunSheep.Interactor.AgentsBehaviour`).
    2. Implement the behaviour in the real module.
    3. Call `Mox.defmock(FunSheep.X.YMock, for: FunSheep.X.YBehaviour)` in
       `test/test_helper.exs`.
    4. Point the corresponding Application env key at the mock in
       `config/test.exs`.
  """
end
