///|
test "response control document writes params" {
  assert_eq(
    response_control_document(["response-content-type", "response-expires"]),
    "<ResponseControlConfiguration><ControlParamList>" +
    "<Param>response-content-type</Param><Param>response-expires</Param>" +
    "</ControlParamList></ResponseControlConfiguration>",
  )
}

///|
test "response control parse reads params" {
  let params = parse_response_control(
    "<ResponseControlConfiguration><ControlParamList>" +
    "<Param>response-cache-control</Param></ControlParamList></ResponseControlConfiguration>",
  )
  assert_eq(params, ["response-cache-control"])
}
