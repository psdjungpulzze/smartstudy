ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(FunSheep.Repo, :manual)
Mox.defmock(FunSheep.Interactor.AgentsMock, for: FunSheep.Interactor.AgentsBehaviour)
Mox.defmock(FunSheep.AI.ClientMock, for: FunSheep.AI.ClientBehaviour)
