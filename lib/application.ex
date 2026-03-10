defmodule DDMon.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      # This explicitly starts the pg scope and links it to this supervisor.
      # If the pg scope crashes, the supervisor will automatically restart it.
      %{
        id: :mon_reg_scope,
        start: {:pg, :start_link, [:mon_reg_scope]}
      }
    ]

    opts = [strategy: :one_for_one, name: DDMon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
