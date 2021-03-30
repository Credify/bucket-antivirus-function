
import io
import sys
import json
from json import JSONDecodeError
from contextlib import redirect_stdout
from peepdf.main import main as peepdf_scanner

def is_javascript_found(path):
    # tokens used by peepdf in analysis result to indicate javascript was found
    vulnerable_tokens = ['/JS', '/Javascript']

    print("Starting peepdf scan of %s." % path)

    # method peepdf_scanner() uses argsParser because it is a cmd line tool.
    # So we need to pass arguments as it was called from the cmd-line.
    sys.argv = [None, path, '--json']
    with io.StringIO() as buf, redirect_stdout(buf):
        peepdf_scanner()
        output = buf.getvalue()
    print(output)

    try:
        raw_json_string = json.loads(output)
    except JSONDecodeError:
        print('Error while executing peepdf. Could not parse result into JSON.')
        sys.exit(1)

    try:
        analysis_result = raw_json_string['peepdf_analysis']['advanced'][0]['version_info']
    except KeyError as e:
        print("Key in json couldn't be found.\nError: {0}".format(e))
        sys.exit(1)

    if 'suspicious_elements' in analysis_result:
        suspisious_elements = analysis_result['suspicious_elements']['actions']
        for token in vulnerable_tokens:
            if suspisious_elements and token in suspisious_elements:
                return True
    return False