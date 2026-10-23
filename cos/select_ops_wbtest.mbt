///|
test "select document keeps the expression plain" {
  assert_eq(
    select_csv_document(
      "SELECT * FROM object",
      record_delimiter="\n",
      field_delimiter=",",
    ),
    "<SelectRequest><Expression>SELECT * FROM object</Expression>" +
    "<ExpressionType>SQL</ExpressionType><InputSerialization><CSV>" +
    "<RecordDelimiter>\n</RecordDelimiter><FieldDelimiter>,</FieldDelimiter>" +
    "</CSV></InputSerialization><OutputSerialization><CSV>" +
    "<RecordDelimiter>\n</RecordDelimiter></CSV></OutputSerialization></SelectRequest>",
  )
}
