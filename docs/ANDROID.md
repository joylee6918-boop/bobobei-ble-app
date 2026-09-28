# Android port outline

The packet format is platform independent. On Android, implement the same state
machine with the native BLE APIs:

- `BluetoothLeScanner.startScan()`; filter advertised/local names starting with
  `SOSEXY`.
- `BluetoothDevice.connectGatt()` and rediscover after reconnect.
- Find service EE01, write characteristic EE03, and optional notify
  characteristic EE02.
- Serialize writes. Wait for `BluetoothGattCallback.onCharacteristicWrite`
  before sending the next 12-byte frame.
- On Android 12+, request the appropriate `BLUETOOTH_SCAN` and
  `BLUETOOTH_CONNECT` runtime permissions.
- For sustained work outside the visible Activity, use a foreground service and
  follow current Android background-execution requirements.

Do not merely translate the Swift syntax: preserve its single-flight GATT write
queue, 400 ms one-packet keepalive, timeout, rediscovery, and reconnect logic.
