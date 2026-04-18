defmodule StudySmartWeb.PageController do
  use StudySmartWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
