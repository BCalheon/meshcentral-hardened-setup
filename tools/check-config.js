// Validates the keys used in config.json against MeshCentral's bundled JSON schema.
// Usage: node check-config.js /opt/meshcentral /path/to/meshcentral-config-schema.json
// The schema is not shipped in the npm package; download it from the MeshCentral GitHub repo.
const path = require('path');
const root = process.argv[2] || '/opt/meshcentral';
const schema = require(path.resolve(process.argv[3] || 'meshcentral-config-schema.json'));
const config = require(path.join(root, 'meshcentral-data/config.json'));

const find = (obj, key) => obj && Object.keys(obj).find(k => k.toLowerCase() === key.toLowerCase());
let problems = 0;

function check(cfg, sch, prefix) {
  for (const key of Object.keys(cfg)) {
    if (key.startsWith('$') || key.startsWith('_')) continue;
    const match = find(sch, key);
    if (!match) { console.log(`UNKNOWN  ${prefix}${key}`); problems++; continue; }
    console.log(`ok       ${prefix}${key}`);
    const sub = sch[match];
    const v = cfg[key];
    if (v && typeof v === 'object' && !Array.isArray(v) && sub && sub.properties) check(v, sub.properties, `${prefix}${key}.`);
  }
}

check(config.settings, schema.properties.settings.properties, 'settings.');
check(config.domains[''], schema.properties.domains.additionalProperties.properties, 'domains[""].');
if (config.letsencrypt) check(config.letsencrypt, schema.properties.letsencrypt.properties, 'letsencrypt.');
console.log(problems ? `\n${problems} unknown key(s)` : '\nAll keys found in schema.');
process.exit(problems ? 1 : 0);
