This minimal application demonstrates the effects of proxy processes on standard GenServer synchronization techniques.

When interacting with GenServers asynchronously (e.g., via `GenServer.cast/2`), 
a common pattern to ensure all messages have been processed before a test or script 
exits is to issue a synchronous call immediately after the casts. Because Erlang 
guarantees message ordering between two processes, a synchronous call like 
`:sys.get_status/1` acts as a barrier, waiting at the back of the mailbox queue 
until all preceding messages are handled.

The `Showcase` module illustrates what happens when a monitoring proxy (`ddmon`) is introduced:

* `test_mail_wait/1`: Uses standard `:sys.get_status/1` on a standard GenServer. 
The caller successfully waits for the worker to process all 20 messages.

* `test_monitored_wait/1`: Uses `:sys.get_status/1` on a proxied GenServer. 
The caller syncs with the *proxy*, not the worker. The proxy finishes quickly 
and replies, allowing the caller to exit before the inner worker finishes 
processing the forwarded messages. This results in dropped messages.

* `test_monitored_wait_corrected/1`: Uses `DDMon.Test.get_status/1` to unwrap 
the proxy and sync directly with the underlying worker, restoring deterministic 
execution and ensuring all logs are printed.