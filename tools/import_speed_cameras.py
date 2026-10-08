"""Extract fixed cameras: pip install osmium; python tools/import_speed_cameras.py INPUT.osm.pbf.
Input: https://download.geofabrik.de/europe/latvia-latest.osm.pbf
OSM contributors, ODbL: https://www.openstreetmap.org/copyright
"""
import argparse, datetime, json, math
from pathlib import Path
import osmium

class Cameras(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.cameras = []
    def node(self, node):
        if node.tags.get('highway') != 'speed_camera' or not node.location.valid():
            return
        lat, lon = node.location.lat, node.location.lon
        if not (math.isfinite(lat) and math.isfinite(lon) and 55 <= lat <= 59 and 20 <= lon <= 29):
            raise ValueError('Invalid Latvia camera coordinate')
        self.cameras.append({'id': 'osm-node-' + str(node.id), 'lat': lat, 'lon': lon})

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input')
    parser.add_argument('--output', default='assets/globe/speed_cameras_lv.json')
    args = parser.parse_args()
    handler = Cameras()
    handler.apply_file(args.input)
    cameras = sorted(handler.cameras, key=lambda camera: camera['id'])
    if not cameras or len({camera['id'] for camera in cameras}) != len(cameras):
        raise ValueError('Empty or duplicate camera dataset; existing snapshot preserved')
    data = {'region': 'Latvia', 'importedAt': datetime.date.today().isoformat(),
            'source': 'https://download.geofabrik.de/europe/latvia-latest.osm.pbf',
            'attribution': '© OpenStreetMap contributors',
            'license': 'https://opendatacommons.org/licenses/odbl/1-0/',
            'cameras': cameras}
    output = Path(args.output)
    temporary = output.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    temporary.replace(output)
    print(f'Imported {len(cameras)} mapped fixed cameras ({output.stat().st_size} bytes)')
