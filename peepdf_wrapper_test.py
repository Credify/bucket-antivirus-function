import unittest
import peepdf_wrapper as subject
import os

TESTDATA_FILENAME_INFECTED = os.path.join(os.path.dirname(__file__), 'test_data/peepdf_json_test_infected.json')
TESTDATA_FILENAME_CLEAN = os.path.join(os.path.dirname(__file__), 'test_data/peepdf_json_test_clean.json')
TESTDATA_FILENAME_UNEXPECTED = os.path.join(os.path.dirname(__file__), 'test_data/peepdf_json_test_unexpected.json')


def read_file(filename: str) -> str:
    with open(filename, 'r') as f:
        return f.read()


class TestPeepdfWrapper(unittest.TestCase):

    def test_givenIsJavascriptFound_whenFileInfected_thenReturnTrue(self):
        subject.peepdf_scanner = lambda: print(read_file(TESTDATA_FILENAME_INFECTED))

        actual = subject.is_javascript_found('whatever')

        self.assertEqual(True, actual)

    def test_givenIsJavascriptFound_whenFileClean_thenReturnFalse(self):
        subject.peepdf_scanner = lambda: print(read_file(TESTDATA_FILENAME_CLEAN))

        actual = subject.is_javascript_found('whatever')

        self.assertEqual(False, actual)

    def test_givenIsJavascriptFound_whenPeepdfExitWithError_thenExit(self):
        subject.peepdf_scanner = lambda: print('ERROR')

        with self.assertRaises(SystemExit) as actual:
            subject.is_javascript_found('whatever')

        self.assertEqual(1, actual.exception.code)

    def test_givenIsJavascriptFound_whenPeepdfResultFormatUnexpected_thenExit(self):
        subject.peepdf_scanner = lambda: print(read_file(TESTDATA_FILENAME_UNEXPECTED))

        with self.assertRaises(SystemExit) as actual:
            subject.is_javascript_found('whatever')

        self.assertEqual(1, actual.exception.code)




