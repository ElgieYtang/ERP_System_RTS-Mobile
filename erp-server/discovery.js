const dgram = require('dgram');
const os = require('os');

const DISCOVER_PROBE = 'RC_ERP_DISCOVER';

function getLanIPv4() {
  const candidates = [];
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const net of entries) {
      if (net.family !== 'IPv4' && net.family !== 4) continue;
      if (net.internal) continue;
      candidates.push(net.address);
    }
  }
  return (
    candidates.find((a) => a.startsWith('192.168.')) ||
    candidates.find((a) => a.startsWith('10.')) ||
    candidates.find((a) => a.startsWith('172.')) ||
    candidates[0] ||
    '127.0.0.1'
  );
}

function startDiscoveryServer(apiPort) {
  const port = Number(process.env.DISCOVER_PORT || 8001);
  const socket = dgram.createSocket('udp4');

  socket.on('message', (msg, rinfo) => {
    if (msg.toString('utf8').trim() !== DISCOVER_PROBE) return;
    const host = getLanIPv4();
    const payload = JSON.stringify({
      api: `http://${host}:${apiPort}/api/mobile`,
      host,
      port: apiPort,
    });
    socket.send(payload, rinfo.port, rinfo.address, () => {});
  });

  socket.bind(port, '0.0.0.0', () => {
    console.log(`LAN discovery listening on UDP ${port}`);
  });
}

module.exports = { startDiscoveryServer };
