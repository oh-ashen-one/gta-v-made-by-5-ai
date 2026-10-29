import json
from pathlib import Path
import tempfile
import unittest

import audit_recovery as audit


def put(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True))
    return {'file': path.name, 'bytes': path.stat().st_size, 'sha256': audit.digest(path)}


class RecoveredPayloadProof(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.reference = Path(self.scratch.name) / 'reference'
        self.recovered = Path(self.scratch.name) / 'recovered'
        for root, seconds in ((self.reference, 1), (self.recovered, 2)):
            graph = put(root / 'graph.json', {'original_nodes': [1, 2], 'mode': 3})
            mesh = put(root / 'mesh.json', {'faces': [[0, 0, 0], [1, 0, 0], [0, 0, 1]]})
            manifest = put(root / 'manifest.json', {
                'city_identity_sha256': 'source-city', 'graph_chunks': [graph],
                'physical_tiles': [mesh], 'resources': {'wall_seconds': seconds},
                'owned_ingest_reuse': None,
            })
            put(root / 'identity.json', {'schema': 'roads', 'manifest': manifest})
            put(root / 'supervisor.json', {'worker_exit': 0, 'status': 'complete_compile_not_runtime_acceptance'})
            (root / 'work.sqlite').write_bytes(b'test-database')

    def tearDown(self):
        self.scratch.cleanup()

    def test_accepts_new_timing_identity_only_after_identical_payloads(self):
        result = audit.audit(self.reference, self.recovered)
        self.assertNotEqual(result['original_identity_sha256'], result['recovered_identity_sha256'])
        self.assertEqual(result['graph_chunks_verified'], 1)
        self.assertEqual(result['physical_tiles_verified'], 1)
        self.assertFalse(result['native_or_semantic_v2_or_world_acceptance'])

    def test_rejects_validly_rehashed_changed_payload_contract(self):
        graph = put(self.recovered / 'graph.json', {'original_nodes': [1, 3], 'mode': 3})
        data = json.loads((self.recovered / 'manifest.json').read_text())
        data['graph_chunks'] = [graph]
        manifest = put(self.recovered / 'manifest.json', data)
        put(self.recovered / 'identity.json', {'schema': 'roads', 'manifest': manifest})
        with self.assertRaisesRegex(ValueError, 'source/geometry contract differs'):
            audit.audit(self.reference, self.recovered)

    def test_rejects_payload_tamper_even_when_manifest_matches(self):
        (self.recovered / 'mesh.json').write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'Artifact descriptor differs'):
            audit.audit(self.reference, self.recovered)

    def test_rejects_unfinished_compiler_even_with_exact_payloads(self):
        put(self.recovered / 'supervisor.json', {'worker_exit': None, 'status': 'running'})
        with self.assertRaisesRegex(ValueError, 'did not terminate'):
            audit.audit(self.reference, self.recovered)


if __name__ == '__main__':
    unittest.main()
