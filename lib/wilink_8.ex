defmodule BlueHeron.Wilink8 do
  require Logger

  def init(path, gpio_bt_en, tty) do
    bts = BlueHeron.BTS.decode_file!(path)
    {:ok, pid} = Circuits.UART.start_link()
    {:ok, pin_ref} = Circuits.GPIO.open(gpio_bt_en, :output)
    Circuits.GPIO.write(pin_ref, 0)
    Process.sleep(5)
    Circuits.GPIO.write(pin_ref, 1)
    Process.sleep(200)

    opts = [
      speed: 115200,
      framing: BlueHeronTransportUART.Framing,
      active: false,
      flow_control: :hardware
    ]

    :ok = Circuits.UART.open(pid, tty, opts)

    state = %{pin_ref: pin_ref, pid: pid, tty: tty, opts: opts}
    upload(bts.actions, state)
  end

  def upload([%{type: :action_remarks, data: remark} | rest], state) do
    Logger.info("TEXAS Remark: #{remark}")
    upload(rest, state)
  end

  def upload([%{type: :action_send_command, data: <<1, _::binary>> = packet} | rest], state) do
    Logger.debug("sending HCI packet: #{inspect(packet, base: :hex, limit: :infinity)}")
    :ok = Circuits.UART.write(state.pid, packet)
    upload(rest, state)
  end

  def upload(
        [%{type: :action_wait_event, data: %{msec: timeout, wait_data: wait_data}} | rest],
        state
      ) do
    case Circuits.UART.read(state.pid, timeout) do
      {:ok, ^wait_data} ->
        upload(rest, state)

      {:ok, bad} ->
        Logger.error(%{
          unexpected_bts_data: inspect(bad, base: :hex, limit: :infinity),
          expected: inspect(wait_data, limit: :infinity, base: :hex)
        })

        upload(rest, state)

      error ->
        error
    end
  end

  def upload([%{type: :action_serial, data: %{baud: _baud, flow: _flow}} | rest], state) do
    upload(rest, state)
    # Logger.warn("changing baud: #{baud} #{flow}")
    # updated_opts = Keyword.put(state.opts, :speed, baud)
    # # :ok = Circuits.UART.configure(state.pid,updated_opts)
    # :ok =
    #   Circuits.UART.configure(state.pid,
    #     speed: 3_000_000,
    #     framing: BlueHeronTransportUART.Framing,
    #     active: false,
    #     flow_control: :hardware
    #   )
    # upload(rest, %{state | opts: updated_opts})
  end

  def upload([], state) do
    # :ok = Circuits.UART.close(state.pid)
    # Process.sleep(1000)
    %BlueHeronTransportUART{
      device: state.tty,
      uart_pid: state.pid,
      uart_opts: state.opts
    }
  end
end
