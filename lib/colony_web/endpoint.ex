defmodule ColonyWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :colony

  socket("/socket", ColonyWeb.UserSocket, websocket: true, longpoll: false)

  plug(ColonyWeb.Static)
  plug(:not_found)

  defp not_found(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(404, "Not found")
  end
end
