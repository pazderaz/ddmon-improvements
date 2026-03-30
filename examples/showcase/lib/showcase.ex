defmodule Showcase do
  @default_message "Hello, World!"

  require Logger

  def test_mail_wait(message \\ @default_message) do
    pid = test_mailbox(Mailbox, message)
    # This will correctly wait just long enough for the mailbox to process the messages.
    :sys.get_status(pid)
  end

  def test_monitored_wait(message \\ @default_message) do
    pid = test_mailbox(MonitoredMailbox, message)
    # This will sometimes give enough time to process the messages, but often not enough
    # because we are testing the proxy, not the actual mailbox.
    :sys.get_status(pid)
  end

  def test_monitored_wait_corrected(message \\ @default_message) do
    pid = test_mailbox(MonitoredMailbox, message)
    # The helper now correctly waits for the actual mailbox (not the proxy) to process the messages.
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
