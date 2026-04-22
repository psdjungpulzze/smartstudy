ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(FunSheep.Repo, :manual)
Mox.defmock(FunSheep.Interactor.AgentsMock, for: FunSheep.Interactor.AgentsBehaviour)
