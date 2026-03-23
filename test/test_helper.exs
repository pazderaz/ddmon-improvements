
Application.ensure_all_started(:logger)
Application.ensure_all_started(MicrochipFactory.Registry)

ExUnit.start()
