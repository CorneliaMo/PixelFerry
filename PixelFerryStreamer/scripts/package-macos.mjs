import { rm, mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { packager } from '@electron/packager';
import { makeUniversalApp } from '@electron/universal';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'out');
const universal = path.join(output, 'universal', 'PixelFerry Streamer.app');
const manifest = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
const buildVersion = process.env.PIXELFERRY_BUILD_NUMBER || '1';

if (!/^[1-9][0-9]*$/.test(buildVersion)) {
  throw new Error('PIXELFERRY_BUILD_NUMBER must be a positive integer');
}

await rm(output, { recursive: true, force: true });
await mkdir(path.dirname(universal), { recursive: true });

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

const [armApp] = await packager({ ...common, arch: 'arm64' });
const [intelApp] = await packager({ ...common, arch: 'x64' });
await makeUniversalApp({
  arm64AppPath: armApp,
  x64AppPath: intelApp,
  outAppPath: universal,
  force: true,
});

console.log(universal);
