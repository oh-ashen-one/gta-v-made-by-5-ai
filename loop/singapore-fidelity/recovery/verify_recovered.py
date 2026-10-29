"""Verify recovered data bytes against pre-restart pinned identities; no engine."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
PINS = {
    'city': ('identity.json', '8b84896f8c9134b5933b2f6c3b036d025a1120d526ab12668e32181d4f148963'),
    'terrain': ('terrain-identity.json', 'f8488742dd93726276b33ca12cda7c6d0a38b967123a0be0d574b9145b7f469c'),
}


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def target(root, relative):
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ValueError('Artifact path escapes its dataset')
    resolved = root / path
    if any(p.is_symlink() for p in [resolved, *resolved.parents]):
        raise ValueError('Artifact inventory crosses a symlink')
    return resolved


def verify(kind, directory):
    directory = directory.absolute()
    entry, pin = PINS[kind]
    checked = set()
    byte_count = 0

    def check(relative, expected, size=None):
        nonlocal byte_count
        path = target(directory, relative)
        if size is not None and path.stat().st_size != size:
            raise ValueError('Artifact size mismatch: ' + relative)
        actual = digest(path)
        if actual != expected:
            raise ValueError('Artifact hash mismatch: ' + relative + ': ' + actual)
        if relative not in checked:
            checked.add(relative)
            byte_count += path.stat().st_size
        return path

    identity_path = check(entry, pin)
    outer = json.loads(identity_path.read_text())
    if kind == 'terrain':
        inner = outer['geometry_identity']
        identity = json.loads(check(inner['file'], inner['sha256'], inner['bytes']).read_text())
        water = outer['water_registry']
        check(water['file'], water['sha256'], water['bytes'])
    else:
        identity = outer
    manifest_item = identity['manifest']
    manifest_path = check(manifest_item['file'], manifest_item['sha256'], manifest_item['bytes'])
    manifest = json.loads(manifest_path.read_text())
    for item in manifest['catalogs']:
        check(item['file'], item['sha256'], item['bytes'])
    for item in manifest['meshes']:
        check(item['file'], item['sha256'], item['bytes'])
        check(item['binary_file'], item['binary_sha256'], item['binary_bytes'])
    return {'kind': kind, 'status': 'EXACT_PIN_AND_FULL_INVENTORY_MATCH',
            'observed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'directory': str(directory), 'identity_sha256': pin,
            'manifest_sha256': manifest_item['sha256'], 'verified_files': len(checked),
            'verified_bytes': byte_count, 'catalogs': len(manifest['catalogs']),
            'mesh_tiles': len(manifest['meshes']), 'counts': manifest.get('counts', {}),
            'source_pin_changed': False, 'engine_or_gameplay_acceptance': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind', choices=PINS)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    if args.receipt.exists():
        raise ValueError('Refusing to replace prior verification evidence')
    result = verify(args.kind, args.directory)
    args.receipt.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
