"""Exercise the scanner's persistent request protocol without desktop state."""
import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
source = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ai_scanner', source / 'scripts/antigravity_usage_scanner.py')
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)


class WorkerTests(unittest.TestCase):
    def test_requests_reuse_worker_and_preserve_quota_policy(self):
        requests = io.StringIO('{"quota":true}\ninvalid\n{"quota":false}\n')
        output = io.StringIO()
        with patch.object(sys, 'argv', ['scanner', '--serve', '/temporary']), \
             patch.object(sys, 'stdin', requests), patch.object(sys, 'stdout', output), \
             patch.object(scanner, 'scan', return_value={'ready': True}) as scan:
            scanner.main()
        self.assertEqual([call.kwargs['include_quota'] for call in scan.call_args_list], [True, False])
        rows = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([row['ready'] for row in rows], [True, False, True])


if __name__ == '__main__':
    unittest.main()
