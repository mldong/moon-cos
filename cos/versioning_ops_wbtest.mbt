///|
test "versioning rejects unknown status" {
  let mut rejected = false
  check_versioning_status("On") catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
