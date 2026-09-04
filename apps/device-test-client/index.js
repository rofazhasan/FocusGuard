#!/usr/bin/env node
/**
 * FocusGuard Device Test Client CLI
 */

const FocusGuardDeviceClient = require('./device-client.js');

async function main() {
  const args = process.argv.slice(2);
  const client = new FocusGuardDeviceClient();

  const initResult = await client.initialize();

  if (args.includes('--status')) {
    console.log(`Device ID: ${client.deviceId || 'None'}`);
    console.log(`State: ${client.state}`);
    console.log(`Has Credentials: ${initResult.paired}`);
    return;
  }

  if (args.includes('--pair')) {
    const codeIndex = args.indexOf('--pair') + 1;
    const code = args[codeIndex];
    if (!code) {
      console.error('Error: Provide pairing session ID or code: --pair <SESSION_ID|CODE>');
      process.exit(1);
    }

    console.log(`==> Submitting pairing request with code/session: ${code}...`);
    const reqResult = await client.startPairing(code);
    console.log(`✓ Request submitted. Status: ${reqResult.status}. Polling for owner approval...`);

    try {
      const approved = await client.pollForApproval(reqResult.sessionId || code, 60, 1000);
      console.log(`🎉 Device enrolled successfully!`);
      console.log(`Device ID: ${approved.deviceId}`);
      console.log(`Credentials saved locally. Reconnection ready without re-pairing.`);
    } catch (err) {
      console.error(`✗ Pairing error: ${err.message}`);
      process.exit(1);
    }
    return;
  }

  if (args.includes('--heartbeat')) {
    try {
      const hb = await client.sendHeartbeat();
      console.log(`✓ Heartbeat acknowledged. Status: ${hb.deviceStatus}, Server Time: ${hb.serverTime}`);
    } catch (err) {
      console.error(`✗ Heartbeat failed: ${err.message}`);
      process.exit(1);
    }
    return;
  }

  if (args.includes('--sync')) {
    try {
      const syncRes = await client.syncPolicies();
      console.log(`✓ Synchronized ${syncRes.policies.length} policies (v${syncRes.policyVersion}).`);
    } catch (err) {
      console.error(`✗ Policy sync failed: ${err.message}`);
      process.exit(1);
    }
    return;
  }

  if (args.includes('--clear')) {
    await client.store.clearCredentials();
    console.log('✓ Cleared local credentials.');
    return;
  }

  console.log('FocusGuard Device Test Client');
  console.log('Usage:');
  console.log('  node index.js --pair <SESSION_ID|CODE>   Start pairing flow');
  console.log('  node index.js --status                   Show client state');
  console.log('  node index.js --heartbeat                Send heartbeat');
  console.log('  node index.js --sync                     Sync policies');
  console.log('  node index.js --clear                    Clear saved credentials');
}

if (require.main === module) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = FocusGuardDeviceClient;
