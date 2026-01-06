import struct Foundation.Calendar
import struct Foundation.Date

func makeFileHeader() -> String {
  return """
  /*
    WARNING:

    This file's contents are automatically generated as part of the module's build process.

    Changes manually made will be lost!
  */
  """
}
