defmodule Showcase do
  @default_message "Hello, World!"

  require Logger

  def test_mail_wait(message \\ @default_message) do
    pid = test_mailbox(Mailbox, message)
    :sys.get_status(pid)
  end

  def test_monitored_wait(message \\ @default_message) do
    pid = test_mailbox(MonitoredMailbox, message)
    :sys.get_status(pid)
  end

  def test_monitored_wait_corrected(message \\ @default_message) do
    pid = test_mailbox(MonitoredMailbox, message)
    DDMon.Test.get_status(pid)
  end

  def test_mailbox(module, message \\ @default_message) do
    {:ok, pid} = module.start()

    Logger.info("Sending mail to MonitoredMailbox with message: #{message}")
    Enum.each(1..100, fn i ->
      module.send_mail("#{message} (#{i})")
    end)

    pid
  end
end
