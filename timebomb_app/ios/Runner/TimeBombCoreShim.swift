import Foundation

@_cdecl("tb_ios_keep_alive")
public func tb_ios_keep_alive() {
  _ = tb_ios_init_session
  _ = tb_ios_register_event_callback
  _ = tb_ios_process_incoming_message
  _ = tb_ios_build_message
  _ = tb_ios_get_session_state
  _ = tb_ios_reset_session
  _ = tb_ios_last_error_message
  _ = tb_ios_free_rust_buffer
  _ = tb_ios_free_c_string
}

@_cdecl("tb_ios_init_session")
public func tb_ios_init_session(_ user_id: UnsafePointer<CChar>?) -> Bool {
  guard let user_id else {
    return false
  }
  return tb_init_session(user_id)
}

@_cdecl("tb_ios_register_event_callback")
public func tb_ios_register_event_callback(_ callback: DartEventCallback?) -> Bool {
  guard let callback else {
    return false
  }
  return tb_register_event_callback(callback)
}

@_cdecl("tb_ios_process_incoming_message")
public func tb_ios_process_incoming_message(_ data: UnsafePointer<UInt8>?, _ len: Int) -> Bool {
  guard let data else {
    return false
  }
  return tb_process_incoming_message(data, len)
}

@_cdecl("tb_ios_build_message")
public func tb_ios_build_message(
  _ instruction: UInt8,
  _ transport: UInt8,
  _ payload_json: UnsafePointer<CChar>?
) -> RustBuffer {
  guard let payload_json else {
    return RustBuffer(ptr: nil, len: 0, cap: 0)
  }
  return tb_build_message(instruction, transport, payload_json)
}

@_cdecl("tb_ios_get_session_state")
public func tb_ios_get_session_state() -> UnsafeMutablePointer<CChar>? {
  tb_get_session_state()
}

@_cdecl("tb_ios_reset_session")
public func tb_ios_reset_session() -> Bool {
  tb_reset_session()
}

@_cdecl("tb_ios_last_error_message")
public func tb_ios_last_error_message() -> UnsafeMutablePointer<CChar>? {
  tb_last_error_message()
}

@_cdecl("tb_ios_free_rust_buffer")
public func tb_ios_free_rust_buffer(_ buffer: RustBuffer) {
  tb_free_rust_buffer(buffer)
}

@_cdecl("tb_ios_free_c_string")
public func tb_ios_free_c_string(_ ptr: UnsafeMutablePointer<CChar>?) {
  tb_free_c_string(ptr)
}
