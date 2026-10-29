from pathlib import Path
from types import SimpleNamespace
import json
import tempfile
import unittest

import audit_profile_country as review
import test_reprofile_country as fixture


class IndependentProfileAuditor(unittest.TestCase):
    def test_matched_graph_profile_passes_and_rehashed_wrong_y_is_rejected(self):
        db=fixture.database()
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);descriptors=review.audit.frozen.export_catalogs(db,root)
            output=root/'audit';output.mkdir()
            args=SimpleNamespace(country=root,country_identity='isolated-fixture',output=output)
            result=review.audit_graph_profile(args,{'graph_chunks':descriptors},db)
            self.assertEqual(result['unique_source_ways'],10)
            self.assertEqual(result['unique_source_vertices'],60)
            descriptor=descriptors[0];path=root/descriptor['file'];graph=json.loads(path.read_bytes())
            graph['vertices'][0]['source_xyz'][1]+=.001
            raw=review.audit.frozen.canonical(graph);path.write_bytes(raw)
            descriptor.update(bytes=len(raw),sha256=review.audit.frozen.sha(raw))
            with self.assertRaisesRegex(ValueError,'new inferred DB profile'):
                review.audit_graph_profile(args,{'graph_chunks':descriptors},db)
        db.close()

    def test_rehashed_direction_corruption_is_rejected(self):
        db=fixture.database()
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);descriptors=review.audit.frozen.export_catalogs(db,root)
            output=root/'audit';output.mkdir();descriptor=descriptors[0]
            graph=json.loads((root/descriptor['file']).read_bytes());graph['edges'][0]['directions']['car']=0
            raw=review.audit.frozen.canonical(graph);(root/descriptor['file']).write_bytes(raw)
            descriptor.update(bytes=len(raw),sha256=review.audit.frozen.sha(raw))
            args=SimpleNamespace(country=root,country_identity='isolated-fixture',output=output)
            with self.assertRaisesRegex(ValueError,'edge/access/direction/grade'):
                review.audit_graph_profile(args,{'graph_chunks':descriptors},db)
        db.close()

    def test_all_failure_rows_are_partitioned_without_truncation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);writer=review.JsonlParts(root,'failures')
            for i in range(20):writer.write({'index':i,'payload':'x'*1_000_000})
            catalog=writer.finish()
            self.assertEqual(catalog['rows'],20);self.assertEqual(len(catalog['parts']),2)
            rows=[]
            for descriptor in catalog['parts']:
                raw=(root/descriptor['file']).read_bytes()
                self.assertLessEqual(len(raw),16*1024*1024)
                self.assertEqual(len(raw),descriptor['bytes'])
                self.assertEqual(review.audit.frozen.sha(raw),descriptor['sha256'])
                rows.extend(json.loads(line)['index'] for line in raw.splitlines())
            self.assertEqual(rows,list(range(20)))


if __name__=='__main__':unittest.main()
