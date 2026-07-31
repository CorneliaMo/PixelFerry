import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { rm, mkdir, readFile, unlink } from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { packager } from '@electron/packager';
import { makeUniversalApp } from '@electron/universal';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'out');
const universal = path.join(output, 'universal', 'PixelFerry Streamer.app');
const manifest = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
const buildVersion = process.env.PIXELFERRY_BUILD_NUMBER || '1';
const electronVersion = manifest.devDependencies.electron;
const electronCache = process.env.PIXELFERRY_ELECTRON_CACHE
  ? path.resolve(process.env.PIXELFERRY_ELECTRON_CACHE)
  : path.join(root, '.cache', 'electron');
const runFile = promisify(execFile);

if (!/^[1-9][0-9]*$/.test(buildVersion)) {
  throw new Error('PIXELFERRY_BUILD_NUMBER must be a positive integer');
}

await rm(output, { recursive: true, force: true });
await mkdir(path.dirname(universal), { recursive: true });
await mkdir(electronCache, { recursive: true });

async function curl(url, destination) {
  await runFile('curl', [
    '--fail',
    '--location',
    '--retry', '3',
    '--retry-all-errors',
    '--connect-timeout', '30',
    '--max-time', '900',
    '--output', destination,
    url,
  ]);
}

async function sha256(file) {
  return createHash('sha256').update(await readFile(file)).digest('hex');
}

const releaseBase = `https://github.com/electron/electron/releases/download/v${electronVersion}`;
const checksumPath = path.join(electronCache, `SHASUMS256-v${electronVersion}.txt`);
console.log(`Downloading Electron ${electronVersion} checksums`);
await curl(`${releaseBase}/SHASUMS256.txt`, checksumPath);
const checksumLines = (await readFile(checksumPath, 'utf8')).split(/\r?\n/);

for (const arch of ['arm64', 'x64']) {
  const fileName = `electron-v${electronVersion}-darwin-${arch}.zip`;
  const expectedLine = checksumLines.find((line) => line.endsWith(` *${fileName}`));
  if (!expectedLine) {
    throw new Error(`Electron checksum is missing for ${fileName}`);
  }
  const expectedHash = expectedLine.slice(0, 64).toLowerCase();
  const destination = path.join(electronCache, fileName);
  let valid = false;
  try {
    valid = (await sha256(destination)) === expectedHash;
  } catch {
    // Cache miss.
  }
  if (!valid) {
    await unlink(destination).catch(() => {});
    console.log(`Downloading ${fileName}`);
    await curl(`${releaseBase}/${fileName}`, destination);
    if ((await sha256(destination)) !== expectedHash) {
      await unlink(destination).catch(() => {});
      throw new Error(`SHA-256 verification failed for ${fileName}`);
    }
  } else {
    console.log(`Using cached ${fileName}`);
  }
}

const common = {
  dir: root,
  out: output,
  name: 'PixelFerry Streamer',
  platform: 'darwin',
  appBundleId: 'cn.corneliamo.PixelFerry.Streamer',
  appCategoryType: 'public.app-category.utilities',
  appVersion: manifest.version,
  buildVersion,
  icon: process.env.PIXELFERRY_ICON || undefined,
  extraResource: [
    path.join(root, 'resources', 'en.lproj'),
    path.join(root, 'resources', 'zh-Hans.lproj'),
  ],
  asar: true,
  overwrite: true,
  prune: true,
  electronZipDir: electronCache,
  extendInfo: {
    CFBundleDisplayName: 'PixelFerry Streamer',
    LSUIElement: true,
    NSLocalNetworkUsageDescription: 'PixelFerry shares a virtual display with browsers on your local network.',
    NSScreenCaptureUsageDescription: 'PixelFerry Streamer captures the PixelFerry virtual display for browser streaming.',
    NSHighResolutionCapable: true,
    NSPrincipalClass: 'AtomApplication',
  },
  ignore: [
    /^\/out($|\/)/,
    /^\/resources($|\/)/,
    /^\/test($|\/)/,
    /^\/scripts($|\/)/,
  ],
};

async function packagedApp(outputDirectory, arch) {
  if (!outputDirectory) {
    throw new Error(`Electron Packager did not return an output directory for ${arch}`);
  }
  const app = path.join(outputDirectory, 'PixelFerry Streamer.app');
  try {
    await readFile(path.join(app, 'Contents', 'Info.plist'));
  } catch {
    throw new Error(`Electron Packager did not create the expected ${arch} app at ${app}`);
  }
  return app;
}

const [armOutput] = await packager({ ...common, arch: 'arm64' });
const armApp = await packagedApp(armOutput, 'arm64');
const [intelOutput] = await packager({ ...common, arch: 'x64' });
const intelApp = await packagedApp(intelOutput, 'x64');
await makeUniversalApp({
  arm64AppPath: armApp,
  x64AppPath: intelApp,
  outAppPath: universal,
  force: true,
});

console.log(universal);
